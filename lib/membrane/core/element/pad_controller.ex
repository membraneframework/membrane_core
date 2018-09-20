defmodule Membrane.Core.Element.PadController do
  @moduledoc false
  # Module handling linking and unlinking pads.

  alias Membrane.{Core, Event}
  alias Core.{CallbackHandler, PullBuffer}
  alias Core.Element.{EventController, PadModel, State}
  alias Membrane.Element.{CallbackContext, Pad}
  alias Bunch.Type
  require CallbackContext.{PadAdded, PadRemoved}
  require Pad
  require PadModel
  use Core.Element.Log
  use Bunch

  @doc """
  Verifies linked pad, initializes it's data.
  """
  @spec handle_link(Pad.ref_t(), Pad.direction_t(), pid, Pad.ref_t(), Keyword.t(), State.t()) ::
          State.stateful_try_t()
  def handle_link(pad_ref, direction, pid, other_ref, props, state) do
    with :ok <- validate_pad_being_linked(pad_ref, direction, state) do
      pad_name = pad_ref |> Pad.name_by_ref()
      info = state.pads.info[pad_name]
      state = init_pad_data(pad_ref, pid, other_ref, props, info, state)

      state =
        case Pad.availability_mode_by_ref(pad_ref) do
          :static ->
            state |> Bunch.Struct.update_in([:pads, :info], &(&1 |> Map.delete(pad_name)))

          :dynamic ->
            add_to_currently_linking(pad_ref, state)
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
        |> Enum.flat_map(fn {name, info} ->
          case info.availability |> Pad.availability_mode() do
            :static -> [name]
            _ -> []
          end
        end)

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
  @spec handle_unlink(Pad.ref_t(), State.t()) :: State.stateful_try_t()
  def handle_unlink(pad_ref, state) do
    PadModel.assert_data!(pad_ref, %{direction: :input}, state)

    with {:ok, state} <- generate_eos_if_not_received(pad_ref, state),
         {:ok, state} <- handle_pad_removed(pad_ref, state),
         {:ok, state} <- PadModel.delete_data(pad_ref, state) do
      {:ok, state}
    end
  end

  @doc """
  Returns a pad reference - a term uniquely identifying pad instance.

  In case of static pad it will be just its name, for dynamic it will return
  tuple containing name and id.
  """
  @spec get_pad_ref(Pad.name_t(), State.t()) :: State.stateful_try_t(Pad.ref_t())
  def get_pad_ref(pad_name, state) do
    {pad_ref, state} =
      state
      |> Bunch.Struct.get_and_update_in([:pads, :info, pad_name], fn
        nil ->
          :pop

        %{availability: av, current_id: id} = pad_info when Pad.is_availability_dynamic(av) ->
          {{:dynamic, pad_name, id}, %{pad_info | current_id: id + 1}}

        %{availability: av} = pad_info when Pad.is_availability_static(av) ->
          {pad_name, pad_info}
      end)

    {pad_ref |> Bunch.error_if_nil(:unknown_pad), state}
  end

  @spec validate_pad_being_linked(Pad.ref_t(), Pad.direction_t(), State.t()) :: Type.try_t()
  defp validate_pad_being_linked(pad_ref, direction, state) do
    info = state.pads.info[pad_ref]

    cond do
      info == nil ->
        case PadModel.assert_instance(pad_ref, state) do
          :ok -> {:error, :already_linked}
          _ -> {:error, :unknown_pad}
        end

      (actual_av_mode = Pad.availability_mode(info.availability)) !=
          (expected_av_mode = Pad.availability_mode_by_ref(pad_ref)) ->
        {:error,
         {:invalid_pad_availability_mode, expected: expected_av_mode, actual: actual_av_mode}}

      info.direction != direction ->
        {:error, {:invalid_pad_direction, expected: direction, actual: info.direction}}

      true ->
        :ok
    end
  end

  @spec init_pad_data(
          Pad.ref_t(),
          pid,
          Pad.ref_t(),
          props :: Keyword.t(),
          PadModel.pad_info_t(),
          State.t()
        ) :: State.t()
  defp init_pad_data(ref, pid, other_ref, props, info, state) do
    data =
      info
      |> Map.merge(%{
        ref: ref,
        pid: pid,
        other_ref: other_ref,
        caps: nil,
        sos: false,
        eos: false
      })

    data = data |> Map.merge(init_pad_direction_data(data, props, state))
    data = data |> Map.merge(init_pad_mode_data(data, props, state))
    state |> Bunch.Struct.put_in([:pads, :data, ref], data)
  end

  defp init_pad_direction_data(%{direction: :input}, _props, _state), do: %{sticky_messages: []}
  defp init_pad_direction_data(%{direction: :output}, _props, _state), do: %{}

  defp init_pad_mode_data(%{mode: :pull, direction: :input} = data, props, state) do
    %{name: name, pid: pid, other_ref: other_ref, demand_in: demand_in} = data

    :ok =
      pid
      |> GenServer.call({:membrane_demand_in, [demand_in, other_ref]})

    pb =
      PullBuffer.new(
        state.name,
        {pid, other_ref},
        name,
        demand_in,
        props[:pull_buffer] || %{}
      )

    %{buffer: pb, demand: 0}
  end

  defp init_pad_mode_data(%{mode: :pull, direction: :output}, _props, _state), do: %{demand: 0}

  defp init_pad_mode_data(%{mode: :push}, _props, _state), do: %{}

  @spec add_to_currently_linking(Pad.ref_t(), State.t()) :: State.t()
  defp add_to_currently_linking(ref, state),
    do: state |> Bunch.Struct.update_in([:pads, :dynamic_currently_linking], &[ref | &1])

  @spec clear_currently_linking(State.t()) :: State.t()
  defp clear_currently_linking(state),
    do: state |> Bunch.Struct.put_in([:pads, :dynamic_currently_linking], [])

  @spec generate_eos_if_not_received(Pad.ref_t(), State.t()) :: State.stateful_try_t()
  defp generate_eos_if_not_received(pad_ref, state) do
    if not PadModel.get_data!(pad_ref, :eos, state) do
      EventController.handle_event(
        pad_ref,
        %{Event.eos() | payload: :auto_eos, mode: :async},
        state
      )
    else
      {:ok, state}
    end
  end

  @spec handle_pad_added(Pad.ref_t(), State.t()) :: State.stateful_try_t()
  defp handle_pad_added(ref, state) do
    context =
      CallbackContext.PadAdded.from_state(
        state,
        direction: PadModel.get_data!(ref, :direction, state)
      )

    CallbackHandler.exec_and_handle_callback(
      :handle_pad_added,
      ActionHandler,
      [ref, context],
      state
    )
  end

  @spec handle_pad_removed(Pad.ref_t(), State.t()) :: State.stateful_try_t()
  defp handle_pad_removed(ref, state) do
    %{caps: caps, direction: direction, availability: availability} =
      PadModel.get_data!(ref, state)

    if availability |> Pad.availability_mode() == :dynamic do
      context = CallbackContext.PadRemoved.from_state(state, direction: direction, caps: caps)

      CallbackHandler.exec_and_handle_callback(
        :handle_pad_removed,
        ActionHandler,
        [ref, context],
        state
      )
    else
      {:ok, state}
    end
  end
end
