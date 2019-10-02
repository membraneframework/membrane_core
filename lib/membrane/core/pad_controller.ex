defmodule Membrane.Core.PadController do
  @moduledoc false
  # Module handling linking and unlinking pads.

  alias Membrane.{Core, Event, LinkError, Pad}
  alias Core.{CallbackHandler, Message, InputBuffer, PadSpecHandler, PadModel}
  alias Core.Element.{ActionHandler, EventController, State, PlaybackBuffer}
  alias Membrane.Element.CallbackContext
  require CallbackContext.{PadAdded, PadRemoved}
  require Message
  require Pad
  require PadModel
  use Membrane.Log
  use Bunch

  @doc """
  Verifies linked pad, initializes it's data.
  """
  @spec handle_link(
          Pad.ref_t(),
          Pad.direction_t(),
          pid,
          Pad.ref_t(),
          PadModel.pad_info_t() | nil,
          Keyword.t(),
          State.t()
        ) :: State.stateful_try_t(PadModel.pad_info_t())
  def handle_link(pad_ref, direction, pid, other_ref, other_info, props, state) do
    pad_name = pad_ref |> Pad.name_by_ref()
    info = state.pads.info[pad_name]

    with :ok <- validate_pad_being_linked!(pad_ref, direction, info, state),
         :ok <- validate_dir_and_mode!({pad_ref, info}, {other_ref, other_info}) do
      props = parse_link_props!(props, pad_name, state)
      state = init_pad_data(info, pad_ref, pid, other_ref, other_info, props, state)

      state =
        case Pad.availability_mode(info.availability) do
          :static ->
            state |> Bunch.Access.update_in([:pads, :info], &(&1 |> Map.delete(pad_name)))

          :dynamic ->
            add_to_currently_linking(pad_ref, state)
        end

      {{:ok, info}, state}
    else
      {:error, reason} -> raise LinkError, "#{inspect(reason)}"
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

      if not Enum.empty?(static_unlinked) do
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
  Handles situation where pad has been unlinked (e.g. when connected element has been removed from pipline)

  Removes pad data.
  Signals an EoS (via handle_event) to the element if unlinked pad was an input.
  Executes `handle_pad_removed` callback if the pad was dynamic.
  Note: it also flushes all buffers from PlaybackBuffer.
  """
  @spec handle_unlink(Pad.ref_t(), State.t()) :: State.stateful_try_t()
  def handle_unlink(pad_ref, state) do
    with {:ok, state} <- flush_playback_buffer(pad_ref, state),
         {:ok, state} <- generate_eos_if_needed(pad_ref, state),
         {:ok, state} <- handle_pad_removed(pad_ref, state),
         {:ok, state} <- PadModel.delete_data(state, pad_ref) do
      {:ok, state}
    end
  end

  @doc """
  Returns a pad reference - a term uniquely identifying pad instance.

  In case of static pad it will be just its name, for dynamic it will return
  tuple containing name and id.
  """
  @spec get_pad_ref(Pad.name_t(), Pad.dynamic_id_t() | nil, State.t()) ::
          State.stateful_try_t(Pad.ref_t())
  def get_pad_ref(pad_name, id, state) do
    case state.pads.info[pad_name] do
      nil ->
        {{:error, :unknown_pad}, state}

      %{availability: av} = pad_info when Pad.is_availability_dynamic(av) ->
        {pad_ref, pad_info} = get_dynamic_pad_ref(pad_name, id, pad_info)
        state |> Bunch.Access.put_in([:pads, :info, pad_name], pad_info) ~> {{:ok, pad_ref}, &1}

      %{availability: av} when Pad.is_availability_static(av) and id == nil ->
        {{:ok, pad_name}, state}

      %{availability: av} when Pad.is_availability_static(av) and id != nil ->
        {{:error, :id_on_static_pad}, state}
    end
  end

  defp get_dynamic_pad_ref(pad_name, nil, %{current_id: id} = pad_info) do
    {{:dynamic, pad_name, id}, %{pad_info | current_id: id + 1}}
  end

  defp get_dynamic_pad_ref(pad_name, id, %{current_id: old_id} = pad_info) do
    {{:dynamic, pad_name, id}, %{pad_info | current_id: max(id, old_id) + 1}}
  end

  @spec validate_pad_being_linked!(
          Pad.ref_t(),
          Pad.direction_t(),
          PadModel.pad_info_t(),
          State.t()
        ) :: :ok
  defp validate_pad_being_linked!(pad_ref, direction, info, state) do
    cond do
      :ok == PadModel.assert_instance(state, pad_ref) ->
        raise LinkError, "Pad #{inspect(pad_ref)} has already been linked"

      info == nil ->
        raise LinkError, "Unknown pad #{inspect(pad_ref)}"

      info.direction != direction ->
        raise LinkError, """
        Invalid pad direction:
          expected: #{inspect(direction)},
          actual: #{inspect(info.direction)}
        """

      true ->
        :ok
    end
  end

  @spec validate_dir_and_mode!(
          {Pad.ref_t(), info :: PadModel.pad_info_t()},
          {Pad.ref_t(), other_info :: PadModel.pad_info_t()}
        ) :: :ok
  def validate_dir_and_mode!(this, that) do
    with :ok <- do_validate_dm(this, that),
         :ok <- do_validate_dm(that, this) do
      :ok
    end
  end

  defp do_validate_dm(
         {from, %{direction: :output, mode: :pull}},
         {to, %{direction: :input, mode: :push}}
       ) do
    raise LinkError,
          "Cannot connect pull output #{inspect(from)} to push input #{inspect(to)}"
  end

  defp do_validate_dm(_, _) do
    :ok
  end

  @spec parse_link_props!(Keyword.t(), Pad.name_t(), State.t()) :: Keyword.t()
  defp parse_link_props!(props, pad_name, state) do
    {_, pad_spec} =
      state.module.membrane_pads()
      |> PadSpecHandler.add_bin_pads()
      |> Enum.find(fn {k, _} -> k == pad_name end)

    opts_spec = pad_spec.options
    pad_props = parse_pad_props!(pad_name, opts_spec, props[:pad])
    buffer_props = parse_buffer_props!(pad_name, props[:buffer])
    [pad: pad_props, buffer: buffer_props]
  end

  defp parse_pad_props!(_pad_name, nil, nil) do
    {:ok, nil}
  end

  defp parse_pad_props!(pad_name, nil, _props) do
    raise LinkError, "Pad #{inspect(pad_name)} does not define any options"
  end

  defp parse_pad_props!(pad_name, options_spec, props) do
    bunch_field_specs = options_spec |> Bunch.KVList.map_values(&Keyword.take(&1, [:default]))

    case props |> List.wrap() |> Bunch.Config.parse(bunch_field_specs) do
      {:ok, pad_props} ->
        pad_props

      {:error, {:config_field, {:key_not_found, key}}} ->
        raise LinkError, "Missing option #{inspect(key)} for pad #{inspect(pad_name)}"

      {:error, {:config_invalid_keys, keys}} ->
        raise LinkError,
              "Invalid keys in options of pad #{inspect(pad_name)} - #{inspect(keys)}"
    end
  end

  defp parse_buffer_props!(pad_name, props) do
    case InputBuffer.parse_props(props) do
      {:ok, buffer_props} ->
        buffer_props

      {:error, {:config_invalid_keys, keys}} ->
        raise LinkError,
              "Invalid keys in buffer options of pad #{inspect(pad_name)}: #{inspect(keys)}"
    end
  end

  @spec init_pad_data(
          PadModel.pad_info_t(),
          Pad.ref_t(),
          pid,
          Pad.ref_t(),
          PadModel.pad_info_t(),
          props :: Keyword.t(),
          State.t()
        ) :: State.t()
  defp init_pad_data(info, ref, pid, other_ref, other_info, props, state) do
    data =
      info
      |> Map.merge(%{
        pid: pid,
        other_ref: other_ref,
        options: props[:pad],
        caps: nil,
        start_of_stream?: false,
        end_of_stream?: false
      })

    data = data |> Map.merge(init_pad_direction_data(data, props, state))
    data = data |> Map.merge(init_pad_mode_data(data, other_info, props, state))
    data = struct!(Pad.Data, data)
    state |> Bunch.Access.put_in([:pads, :data, ref], data)
  end

  defp init_pad_direction_data(%{direction: :input}, _props, _state), do: %{sticky_messages: []}
  defp init_pad_direction_data(%{direction: :output}, _props, _state), do: %{}

  @spec init_pad_mode_data(
          map(),
          PadModel.pad_info_t(),
          props :: Keyword.t(),
          State.t()
        ) :: map()
  defp init_pad_mode_data(%{mode: :pull, direction: :input} = data, other_info, props, state) do
    %{pid: pid, other_ref: other_ref, demand_unit: demand_unit} = data

    Message.send(pid, :demand_unit, [demand_unit, other_ref])

    buffer_props = props[:buffer] || Keyword.new()

    enable_toilet? = other_info.mode == :push

    input_buf =
      InputBuffer.init(
        state.name,
        demand_unit,
        enable_toilet?,
        pid,
        other_ref,
        buffer_props
      )

    %{input_buf: input_buf, demand: 0}
  end

  defp init_pad_mode_data(%{mode: :pull, direction: :output}, _other_info, _props, _state),
    do: %{demand: 0}

  defp init_pad_mode_data(%{mode: :push}, _other_info, _props, _state), do: %{}

  @spec add_to_currently_linking(Pad.ref_t(), State.t()) :: State.t()
  defp add_to_currently_linking(ref, state),
    do: state |> Bunch.Access.update_in([:pads, :dynamic_currently_linking], &[ref | &1])

  @spec clear_currently_linking(State.t()) :: State.t()
  defp clear_currently_linking(state),
    do: state |> Bunch.Access.put_in([:pads, :dynamic_currently_linking], [])

  @spec generate_eos_if_needed(Pad.ref_t(), State.t()) :: State.stateful_try_t()
  defp generate_eos_if_needed(pad_ref, state) do
    direction = PadModel.get_data!(state, pad_ref, :direction)
    eos? = PadModel.get_data!(state, pad_ref, :end_of_stream?)

    if direction == :input and not eos? do
      EventController.exec_handle_event(pad_ref, %Event.EndOfStream{}, state)
    else
      {:ok, state}
    end
  end

  @spec handle_pad_added(Pad.ref_t(), State.t()) :: State.stateful_try_t()
  defp handle_pad_added(ref, state) do
    pad_opts = PadModel.get_data!(state, ref, :options)

    context =
      &CallbackContext.PadAdded.from_state(
        &1,
        direction: PadModel.get_data!(state, ref, :direction),
        options: pad_opts
      )

    CallbackHandler.exec_and_handle_callback(
      :handle_pad_added,
      ActionHandler,
      %{context: context},
      [ref],
      state
    )
  end

  @spec handle_pad_removed(Pad.ref_t(), State.t()) :: State.stateful_try_t()
  defp handle_pad_removed(ref, state) do
    %{direction: direction, availability: availability} = PadModel.get_data!(state, ref)

    if availability |> Pad.availability_mode() == :dynamic do
      context = &CallbackContext.PadRemoved.from_state(&1, direction: direction)

      CallbackHandler.exec_and_handle_callback(
        :handle_pad_removed,
        ActionHandler,
        %{context: context},
        [ref],
        state
      )
    else
      {:ok, state}
    end
  end

  defp flush_playback_buffer(pad_ref, state) do
    new_playback_buf = PlaybackBuffer.flush_for_pad(state.playback_buffer, pad_ref)
    {:ok, %{state | playback_buffer: new_playback_buf}}
  end
end
