defmodule Membrane.Core.Element.PadController do
  @moduledoc false
  # Module handling linking and unlinking pads.

  alias Membrane.{Core, Event, Type}
  alias Core.{CallbackHandler, PullBuffer}
  alias Core.Element.{EventController, PadModel, State}
  alias Membrane.Element.{CallbackContext, Pad}
  require CallbackContext.{PadAdded, PadRemoved}
  require Pad
  require PadModel
  use Core.Element.Log
  use Bunch

  @doc """
  Verifies linked pad, initializes it's data.
  """
  @spec handle_link(Pad.name_t(), Pad.direction_t(), pid, Pad.name_t(), Keyword.t(), State.t()) ::
          State.stateful_try_t()
  def handle_link(pad_name, direction, pid, other_name, props, state) do
    with :ok <- validate_pad_being_linked(pad_name, direction, state) do
      info = state.pads.info[pad_name]
      state = init_pad_data(pad_name, pid, other_name, props, info, state)

      state =
        case Pad.availability_mode_by_name(pad_name) do
          :static ->
            state |> Bunch.Struct.update_in([:pads, :info], &(&1 |> Map.delete(pad_name)))

          :dynamic ->
            add_to_currently_linking(pad_name, state)
        end

      {:ok, state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @doc """
  Performs checks and executes 'handle_new_pad' callback.

  This can be done only at the end of linking, because before there is no guarantee
  that the pad has been linked in the other element.
  """
  @spec handle_linking_finished(State.t()) :: State.stateful_try_t()
  def handle_linking_finished(state) do
    with {:ok, state} <-
           state.pads.dynamic_currently_linking
           |> Bunch.Enum.try_reduce(state, &handle_pad_added/2) do
      static_unlinked =
        state.pads.info
        |> Map.values()
        |> Enum.filter(&(&1.availability |> Pad.availability_mode() == :dynamic))
        |> Enum.map(& &1.name)

      if static_unlinked |> Enum.empty?() |> Kernel.!() do
        warn(
          """
          Some static pads remained unlinked: #{inspect(static_unlinked)}
          """,
          state
        )
      end

      {:ok, clear_currently_linking(state)}
    end
  end

  @doc """
  Executes `handle_pad_removed` callback for dynamic pads and removes pad data.
  """
  @spec handle_unlink(Pad.name_t(), State.t()) :: State.stateful_try_t()
  def handle_unlink(pad_name, state) do
    PadModel.assert_data!(pad_name, %{direction: :sink}, state)

    with {:ok, state} <- generate_eos_if_not_received(pad_name, state),
         {:ok, state} <- handle_pad_removed(pad_name, state),
         {:ok, state} <- PadModel.delete_data(pad_name, state) do
      {:ok, state}
    end
  end

  @doc """
  Returns pad full name. Full name differs from short name for dynamic pads, for
  which it includes pad id.
  """
  @spec get_pad_full_name(Pad.name_t(), State.t()) :: State.stateful_try_t(Pad.name_t())
  def get_pad_full_name(pad_name, state) do
    {full_name, state} =
      state
      |> Bunch.Struct.get_and_update_in([:pads, :info, pad_name], fn
        nil ->
          :pop

        %{availability: av, current_id: id} = pad_info when Pad.is_availability_dynamic(av) ->
          {{:dynamic, pad_name, id}, %{pad_info | current_id: id + 1}}

        %{availability: av} = pad_info when Pad.is_availability_static(av) ->
          {pad_name, pad_info}
      end)

    {full_name |> Bunch.wrap_nil(:unknown_pad), state}
  end

  @spec validate_pad_being_linked(Pad.name_t(), Pad.direction_t(), State.t()) :: Type.try_t()
  defp validate_pad_being_linked(pad_name, direction, state) do
    info = state.pads.info[pad_name]

    cond do
      info == nil ->
        case PadModel.assert_instance(pad_name, state) do
          :ok -> {:error, :already_linked}
          _ -> {:error, :unknown_pad}
        end

      (actual_av_mode = Pad.availability_mode(info.availability)) !=
          (expected_av_mode = Pad.availability_mode_by_name(pad_name)) ->
        {:error,
         {:invalid_pad_availability_mode, expected: expected_av_mode, actual: actual_av_mode}}

      info.direction != direction ->
        {:error, {:invalid_pad_direction, expected: direction, actual: info.direction}}

      true ->
        :ok
    end
  end

  @spec init_pad_data(
          Pad.name_t(),
          pid,
          Pad.name_t(),
          props :: Keyword.t(),
          PadModel.pad_info_t(),
          State.t()
        ) :: State.t()
  defp init_pad_data(name, pid, other_name, props, info, state) do
    data =
      info
      |> Map.merge(%{
        name: name,
        pid: pid,
        other_name: other_name,
        caps: nil,
        sos: false,
        eos: false
      })

    data = data |> Map.merge(init_pad_direction_data(data, props, state))
    data = data |> Map.merge(init_pad_mode_data(data, props, state))
    state |> Bunch.Struct.put_in([:pads, :data, name], data)
  end

  @spec init_pad_direction_data(PadModel.pad_data_t(), Keyword.t(), State.t()) ::
          PadModel.pad_data_t()
  defp init_pad_direction_data(%{direction: :sink}, _props, _state), do: %{sticky_messages: []}
  defp init_pad_direction_data(%{direction: :source}, _props, _state), do: %{}

  @spec init_pad_mode_data(PadModel.pad_data_t(), Keyword.t(), State.t()) :: PadModel.pad_data_t()
  defp init_pad_mode_data(%{mode: :pull, direction: :sink} = data, props, state) do
    %{name: name, pid: pid, other_name: other_name, options: options} = data

    :ok =
      pid
      |> GenServer.call({:membrane_demand_in, [options.demand_in, other_name]})

    pb =
      PullBuffer.new(
        state.name,
        {pid, other_name},
        name,
        options.demand_in,
        props[:pull_buffer] || %{}
      )

    %{buffer: pb, demand: 0}
  end

  defp init_pad_mode_data(%{mode: :pull, direction: :source}, _props, _state), do: %{demand: 0}

  defp init_pad_mode_data(%{mode: :push}, _props, _state), do: %{}

  @spec add_to_currently_linking(Pad.name_t(), State.t()) :: State.t()
  defp add_to_currently_linking(name, state),
    do: state |> Bunch.Struct.update_in([:pads, :dynamic_currently_linking], &[name | &1])

  @spec clear_currently_linking(State.t()) :: State.t()
  defp clear_currently_linking(state),
    do: state |> Bunch.Struct.put_in([:pads, :dynamic_currently_linking], [])

  @spec generate_eos_if_not_received(Pad.name_t(), State.t()) :: State.stateful_try_t()
  defp generate_eos_if_not_received(pad_name, state) do
    if PadModel.get_data!(pad_name, :eos, state) do
      EventController.handle_event(
        pad_name,
        %{Event.eos() | payload: :auto_eos, mode: :async},
        state
      )
    else
      {:ok, state}
    end
  end

  @spec handle_pad_added(Pad.name_t(), State.t()) :: State.stateful_try_t()
  defp handle_pad_added(name, state) do
    context =
      CallbackContext.PadAdded.from_state(
        state,
        direction: PadModel.get_data!(name, :direction, state)
      )

    CallbackHandler.exec_and_handle_callback(
      :handle_pad_added,
      ActionHandler,
      [name, context],
      state
    )
  end

  @spec handle_pad_removed(Pad.name_t(), State.t()) :: State.stateful_try_t()
  defp handle_pad_removed(name, state) do
    %{caps: caps, direction: direction, availability: availability} =
      PadModel.get_data!(name, state)

    if availability |> Pad.availability_mode() == :dynamic do
      context = CallbackContext.PadRemoved.from_state(state, direction: direction, caps: caps)

      CallbackHandler.exec_and_handle_callback(
        :handle_pad_removed,
        ActionHandler,
        [name, context],
        state
      )
    else
      {:ok, state}
    end
  end
end
