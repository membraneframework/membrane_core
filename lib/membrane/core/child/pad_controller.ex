defmodule Membrane.Core.Child.PadController do
  @moduledoc false

  # Module handling linking and unlinking pads.

  use Bunch
  alias Bunch.Type
  alias Membrane.{Core, LinkError, Pad, ParentSpec}
  alias Membrane.Core.{CallbackHandler, Events, InputBuffer, Message}
  alias Membrane.Core.Bin.LinkingBuffer
  alias Membrane.Core.{CallbackHandler, Component, Message, InputBuffer}
  alias Membrane.Core.Child.{PadModel, PadSpecHandler}
  alias Membrane.Core.Element.{DemandController, EventController, PlaybackBuffer}
  alias Membrane.Core.Parent.LinkParser

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Component
  require Membrane.Core.Message
  require Membrane.Logger
  require Membrane.Pad

  @type state_t :: Core.Bin.State.t() | Core.Element.State.t()

  @typep parsed_pad_props_t :: %{buffer: InputBuffer.props_t(), options: map}

  @doc """
  Verifies linked pad, initializes it's data.
  """
  @spec handle_link(
          Pad.direction_t(),
          LinkParser.raw_endpoint_t(),
          LinkParser.raw_endpoint_t(),
          PadModel.pad_info_t() | nil,
          state_t()
        ) :: Type.stateful_try_t(PadModel.pad_info_t(), state_t)
  def handle_link(direction, this, other, link_metadata, state) do
    name = this.pad_ref |> Pad.name_by_ref()
    info = state.pads.info[name]

    {:ok, link_metadata} =
      if link_metadata do
        {:ok, link_metadata}
      else
        other_direction = Pad.opposite_direction(direction)
        metadata = %{info: info, toilet: :atomics.new(1, [])}
        Message.call(other.pid, :handle_link, [other_direction, other, this, metadata])
      end

    # IO.inspect({direction, this, other, info, link_metadata})

    with :ok <- validate_pad_being_linked!(this.pad_ref, direction, info, state),
         :ok <-
           validate_dir_and_mode!({this.pad_ref, info}, {other.pad_ref, link_metadata.info}) do
      props = parse_pad_props!(this.pad_props, name, state)

      state =
        init_pad_data(this.pad_ref, info, props, other.pad_ref, other.pid, link_metadata, state)

      state =
        case Pad.availability_mode(info.availability) do
          :dynamic -> add_to_currently_linking(this.pad_ref, state)
          :static -> state
        end

      {{:ok, %{link_metadata | info: info}}, state}
    else
      {:error, reason} -> raise LinkError, "#{inspect(reason)}"
    end
  end

  @doc """
  Performs checks and executes 'handle_new_pad' callback.

  This can be done only at the end of linking, because before there is no guarantee
  that the pad has been linked in the other element.
  """
  @spec handle_linking_finished(state_t()) :: Type.stateful_try_t(state_t)
  def handle_linking_finished(state) do
    with {:ok, state} <-
           state.pads.dynamic_currently_linking
           |> Enum.reverse()
           |> Enum.filter(&(&1 |> Pad.name_by_ref() |> Pad.is_public_name()))
           |> Bunch.Enum.try_reduce(state, &handle_pad_added/2) do
      linked_pads_names = state.pads.data |> Map.values() |> Enum.map(& &1.name) |> MapSet.new()

      static_unlinked_pads =
        state.pads.info
        |> Map.values()
        |> Enum.filter(
          &(Pad.availability_mode(&1.availability) == :static and &1.name not in linked_pads_names)
        )

      unless Enum.empty?(static_unlinked_pads) do
        Membrane.Logger.warn("""
        Some static pads remained unlinked: #{inspect(Enum.map(static_unlinked_pads, & &1.name))}
        State: #{inspect(state, pretty: true)}
        """)
      end

      bin? = match?(%Membrane.Core.Bin.State{}, state)

      if bin? do
        LinkingBuffer.flush_all_public_pads(state)
      else
        state
      end
      |> clear_currently_linking()
      ~> {:ok, &1}
    end
  end

  @doc """
  Handles situation where pad has been unlinked (e.g. when connected element has been removed from pipline)

  Removes pad data.
  Signals an EoS (via handle_event) to the element if unlinked pad was an input.
  Executes `handle_pad_removed` callback if the pad was dynamic.
  Note: it also flushes all buffers from PlaybackBuffer.
  """
  @spec handle_unlink(Pad.ref_t(), state_t()) :: Type.stateful_try_t(state_t)
  def handle_unlink(pad_ref, state) do
    with {:ok, state} <- flush_playback_buffer(pad_ref, state),
         {:ok, state} <- generate_eos_if_needed(pad_ref, state),
         {:ok, state} <- handle_pad_removed(pad_ref, state),
         {{:ok, data}, state} <- PadModel.pop_data(state, pad_ref) do
      state = check_for_auto_demands(data, state)
      {:ok, state}
    end
  end

  @spec validate_pad_being_linked!(
          Pad.ref_t(),
          Pad.direction_t(),
          PadModel.pad_info_t(),
          state_t()
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
          expected: #{inspect(info.direction)},
          actual: #{inspect(direction)}
        """

      true ->
        :ok
    end
  end

  @spec validate_dir_and_mode!(
          {Pad.ref_t(), info :: PadModel.pad_info_t()},
          {Pad.ref_t(), other_info :: PadModel.pad_info_t()}
        ) :: :ok
  defp validate_dir_and_mode!(this, that) do
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

  defp do_validate_dm(_pad, _other_pad) do
    :ok
  end

  @spec parse_pad_props!(ParentSpec.pad_props_t(), Pad.name_t(), state_t()) ::
          parsed_pad_props_t | no_return
  defp parse_pad_props!(props, pad_name, state) do
    {_, pad_spec} = PadSpecHandler.get_pads(state) |> Enum.find(fn {k, _} -> k == pad_name end)
    pad_opts = parse_pad_options!(pad_name, pad_spec.options, props[:options])
    buffer_props = parse_buffer_props!(pad_name, props[:buffer])
    %{options: pad_opts, buffer: buffer_props}
  end

  defp parse_pad_options!(_pad_name, nil, nil) do
    nil
  end

  defp parse_pad_options!(pad_name, nil, _props) do
    raise LinkError, "Pad #{inspect(pad_name)} does not define any options"
  end

  defp parse_pad_options!(pad_name, options_spec, props) do
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
          Pad.ref_t(),
          PadModel.pad_info_t(),
          parsed_pad_props_t,
          Pad.ref_t(),
          pid,
          PadModel.pad_info_t(),
          state_t()
        ) :: state_t()
  defp init_pad_data(ref, info, props, other_ref, other_pid, metadata, state) do
    data =
      info
      |> Map.merge(%{
        pid: other_pid,
        other_ref: other_ref,
        options: props.options,
        ref: ref,
        caps: nil,
        start_of_stream?: false,
        end_of_stream?: false
      })

    data = data |> Map.merge(init_pad_direction_data(data, props, state))
    data = data |> Map.merge(init_pad_mode_data(data, props, metadata, state))
    data = struct!(Pad.Data, data)
    state = Bunch.Access.put_in(state, [:pads, :data, ref], data)

    if data.demand_mode == :auto do
      state =
        state.pads.data
        |> Map.values()
        |> Enum.filter(&(&1.direction != data.direction and &1.demand_mode == :auto))
        |> Enum.reduce(state, fn other_data, state ->
          PadModel.update_data!(state, other_data.ref, :demand_pads, &[data.ref | &1])
        end)

      case data.direction do
        :input -> DemandController.check_auto_demand(ref, state)
        :output -> state
      end
    else
      state
    end
  end

  defp init_pad_direction_data(%{direction: :input}, _props, _state), do: %{sticky_messages: []}
  defp init_pad_direction_data(%{direction: :output}, _props, _state), do: %{}

  @spec init_pad_mode_data(map(), parsed_pad_props_t, PadModel.pad_info_t(), state_t()) :: map()

  defp init_pad_mode_data(
         %{mode: :pull, direction: :input, demand_mode: :manual} = data,
         props,
         metadata,
         %Membrane.Core.Element.State{}
       ) do
    %{ref: ref, pid: pid, other_ref: other_ref, demand_unit: demand_unit} = data
    input_buf = InputBuffer.init(demand_unit, pid, other_ref, inspect(ref), props.buffer)

    {toilet, input_buf} =
      if metadata.info.mode == :push do
        {metadata.toilet, InputBuffer.enable_toilet(input_buf)}
      else
        {nil, input_buf}
      end

    %{input_buf: input_buf, demand: 0, toilet: toilet}
  end

  defp init_pad_mode_data(
         %{mode: :pull, direction: :output, demand_mode: :manual},
         _props,
         metadata,
         _state
       ),
       do: %{demand: 0, other_demand_unit: metadata.info[:demand_unit]}

  defp init_pad_mode_data(
         %{mode: :pull, demand_mode: :auto, direction: direction},
         _props,
         metadata,
         %Membrane.Core.Element.State{} = state
       ) do
    demand_pads =
      state.pads.data
      |> Map.values()
      |> Enum.filter(&(&1.direction != direction and &1.demand_mode == :auto))
      |> Enum.map(& &1.ref)

    toilet =
      if direction == :input and metadata.info.mode == :push do
        metadata.toilet
      else
        nil
      end

    %{
      demand: 0,
      demand_pads: demand_pads,
      other_demand_unit: metadata.info[:demand_unit],
      toilet: toilet
    }
  end

  defp init_pad_mode_data(
         %{mode: :push, direction: :output},
         _props,
         %{info: %{mode: :pull}} = metadata,
         _state
       ) do
    Task.start_link(fn ->
      Stream.repeatedly(fn ->
        Process.sleep(1000)
        IO.inspect({_state.name, :atomics.get(metadata.toilet, 1)})
      end)
      |> Stream.run()
    end)

    %{toilet: metadata.toilet, other_demand_unit: metadata.info[:demand_unit]}
  end

  defp init_pad_mode_data(_data, _props, _metadata, _state), do: %{}

  @spec add_to_currently_linking(Pad.ref_t(), state_t()) :: state_t()
  defp add_to_currently_linking(ref, state),
    do: state |> Bunch.Access.update_in([:pads, :dynamic_currently_linking], &[ref | &1])

  @spec clear_currently_linking(state_t()) :: state_t()
  defp clear_currently_linking(state),
    do: state |> Bunch.Access.put_in([:pads, :dynamic_currently_linking], [])

  @spec generate_eos_if_needed(Pad.ref_t(), state_t()) :: Type.stateful_try_t(state_t)
  def generate_eos_if_needed(pad_ref, state) do
    direction = PadModel.get_data!(state, pad_ref, :direction)
    eos? = PadModel.get_data!(state, pad_ref, :end_of_stream?)
    %{state: playback_state} = state.playback

    if direction == :input and not eos? and playback_state == :playing do
      EventController.exec_handle_event(pad_ref, %Events.EndOfStream{}, state)
    else
      {:ok, state}
    end
  end

  @spec handle_pad_added(Pad.ref_t(), state_t()) :: Type.stateful_try_t(state_t)
  defp handle_pad_added(ref, state) do
    %{options: pad_opts, direction: direction} = PadModel.get_data!(state, ref)

    context =
      Component.callback_context_generator(:child, PadAdded, state,
        options: pad_opts,
        direction: direction
      )

    CallbackHandler.exec_and_handle_callback(
      :handle_pad_added,
      get_callback_action_handler(state),
      %{context: context},
      [ref],
      state
    )
  end

  @spec handle_pad_removed(Pad.ref_t(), state_t()) :: Type.stateful_try_t(state_t)
  def handle_pad_removed(ref, state) do
    %{direction: direction, availability: availability} = PadModel.get_data!(state, ref)
    name = Pad.name_by_ref(ref)

    if Pad.availability_mode(availability) == :dynamic and Pad.is_public_name(name) do
      context =
        Component.callback_context_generator(:child, PadRemoved, state, direction: direction)

      CallbackHandler.exec_and_handle_callback(
        :handle_pad_removed,
        get_callback_action_handler(state),
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

  defp check_for_auto_demands(%{mode: :pull, demand_mode: :auto} = pad_data, state) do
    state =
      Enum.reduce(pad_data.demand_pads, state, fn pad, state ->
        PadModel.update_data!(state, pad, :demand_pads, &List.delete(&1, pad_data.ref))
      end)

    if pad_data.direction == :output do
      Enum.reduce(pad_data.demand_pads, state, &DemandController.check_auto_demand/2)
    else
      state
    end
  end

  defp check_for_auto_demands(_pad_data, state) do
    state
  end

  defp get_callback_action_handler(%Core.Element.State{}), do: Core.Element.ActionHandler
  defp get_callback_action_handler(%Core.Bin.State{}), do: Core.Bin.ActionHandler
end
