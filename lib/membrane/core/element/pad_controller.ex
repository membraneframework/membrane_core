defmodule Membrane.Core.Element.PadController do
  @moduledoc false

  # Module handling linking and unlinking pads.

  use Bunch
  alias Bunch.Type
  alias Membrane.{Core, Pad}
  alias Membrane.Core.{CallbackHandler, Child, Events, InputBuffer, Message}
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    ActionHandler,
    DemandController,
    EventController,
    PlaybackBuffer,
    State
  }

  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.Element.CallbackContext

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Element.CallbackContext.{PadAdded, PadRemoved}
  require Membrane.Logger
  require Membrane.Pad

  @typep parsed_pad_props_t :: %{buffer: InputBuffer.props_t(), options: map}

  @doc """
  Verifies linked pad, initializes it's data.
  """
  @spec handle_link(
          Pad.direction_t(),
          Endpoint.t(),
          Endpoint.t(),
          PadModel.pad_info_t() | nil,
          %{toilet: reference()},
          State.t()
        ) ::
          {{:ok, {Endpoint.t(), PadModel.pad_info_t()}}, State.t()}
  def handle_link(direction, this, other, other_info, link_metadata, state) do
    Membrane.Logger.debug(
      "Element handle link on pad #{inspect(this.pad_ref)} with pad #{inspect(other.pad_ref)} of child #{inspect(other.child)}"
    )

    name = this.pad_ref |> Pad.name_by_ref()
    info = Map.fetch!(state.pads.info, name)
    :ok = Child.PadController.validate_pad_being_linked!(this.pad_ref, direction, info, state)

    {other, other_info, link_metadata} =
      if link_metadata do
        {other, other_info, link_metadata}
      else
        other_direction = Pad.opposite_direction(direction)
        metadata = %{toilet: :atomics.new(1, [])}

        {:ok, {other, other_info}} =
          Message.call(other.pid, :handle_link, [other_direction, other, this, info, metadata])

        {other, other_info, metadata}
      end

    :ok =
      Child.PadController.validate_pad_mode!({this.pad_ref, info}, {other.pad_ref, other_info})

    props = Child.PadController.parse_pad_props!(this.pad_props, name, state)

    state =
      init_pad_data(
        this.pad_ref,
        info,
        props,
        other.pad_ref,
        other.pid,
        other_info,
        link_metadata,
        state
      )

    {:ok, state} =
      case Pad.availability_mode(info.availability) do
        :dynamic -> handle_pad_added(this.pad_ref, state)
        :static -> {:ok, state}
      end

    {{:ok, {this, info}}, state}
  end

  @doc """
  Handles situation where pad has been unlinked (e.g. when connected element has been removed from pipline)

  Removes pad data.
  Signals an EoS (via handle_event) to the element if unlinked pad was an input.
  Executes `handle_pad_removed` callback if the pad was dynamic.
  Note: it also flushes all buffers from PlaybackBuffer.
  """
  @spec handle_unlink(Pad.ref_t(), Core.Element.State.t()) ::
          Type.stateful_try_t(Core.Element.State.t())
  def handle_unlink(pad_ref, state) do
    with {:ok, state} <- flush_playback_buffer(pad_ref, state),
         {:ok, state} <- generate_eos_if_needed(pad_ref, state),
         {:ok, state} <- handle_pad_removed(pad_ref, state) do
      state = remove_pad_associations(pad_ref, state)
      state = PadModel.delete_data!(state, pad_ref)
      {:ok, state}
    end
  end

  @spec init_pad_data(
          Pad.ref_t(),
          PadModel.pad_info_t(),
          parsed_pad_props_t,
          Pad.ref_t(),
          pid,
          PadModel.pad_info_t(),
          map,
          Core.Element.State.t()
        ) :: Core.Element.State.t()
  defp init_pad_data(ref, info, props, other_ref, other_pid, other_info, metadata, state) do
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
    data = data |> Map.merge(init_pad_mode_data(data, props, other_info, metadata, state))
    data = struct!(Membrane.Element.PadData, data)
    state = Bunch.Access.put_in(state, [:pads, :data, ref], data)

    if data.demand_mode == :auto do
      state =
        state.pads.data
        |> Map.values()
        |> Enum.filter(&(&1.direction != data.direction and &1.demand_mode == :auto))
        |> Enum.reduce(state, fn other_data, state ->
          PadModel.update_data!(state, other_data.ref, :associated_pads, &[data.ref | &1])
        end)

      case data.direction do
        :input -> DemandController.send_auto_demand_if_needed(ref, state)
        :output -> state
      end
    else
      state
    end
  end

  defp init_pad_direction_data(%{direction: :input}, _props, _state), do: %{sticky_messages: []}
  defp init_pad_direction_data(%{direction: :output}, _props, _state), do: %{}

  @spec init_pad_mode_data(
          map(),
          parsed_pad_props_t,
          PadModel.pad_info_t(),
          map,
          Core.Element.State.t()
        ) ::
          map()
  defp init_pad_mode_data(
         %{mode: :pull, direction: :input, demand_mode: :manual} = data,
         props,
         other_info,
         metadata,
         %Membrane.Core.Element.State{}
       ) do
    %{ref: ref, pid: pid, other_ref: other_ref, demand_unit: demand_unit} = data
    enable_toilet? = other_info.mode == :push

    input_buf =
      InputBuffer.init(demand_unit, pid, other_ref, inspect(ref), enable_toilet?, props.buffer)

    %{input_buf: input_buf, demand: 0, toilet: if(enable_toilet?, do: metadata.toilet)}
  end

  defp init_pad_mode_data(
         %{mode: :pull, direction: :output, demand_mode: :manual},
         _props,
         other_info,
         _metadata,
         _state
       ),
       do: %{demand: 0, other_demand_unit: other_info[:demand_unit]}

  defp init_pad_mode_data(
         %{mode: :pull, demand_mode: :auto, direction: direction},
         _props,
         other_info,
         metadata,
         %Membrane.Core.Element.State{} = state
       ) do
    associated_pads =
      state.pads.data
      |> Map.values()
      |> Enum.filter(&(&1.direction != direction and &1.demand_mode == :auto))
      |> Enum.map(& &1.ref)

    toilet =
      if direction == :input and other_info.mode == :push do
        metadata.toilet
      else
        nil
      end

    %{
      demand: 0,
      associated_pads: associated_pads,
      other_demand_unit: other_info[:demand_unit],
      toilet: toilet
    }
  end

  defp init_pad_mode_data(
         %{mode: :push, direction: :output},
         _props,
         %{mode: :pull} = other_info,
         metadata,
         _state
       ) do
    %{toilet: metadata.toilet, other_demand_unit: other_info[:demand_unit]}
  end

  defp init_pad_mode_data(_data, _props, _other_info, _metadata, _state), do: %{}

  @spec generate_eos_if_needed(Pad.ref_t(), Core.Element.State.t()) ::
          Type.stateful_try_t(Core.Element.State.t())
  def generate_eos_if_needed(pad_ref, state) do
    %{direction: direction, end_of_stream?: eos?} = PadModel.get_data!(state, pad_ref)
    %{state: playback_state} = state.playback

    if direction == :input and not eos? and playback_state == :playing do
      EventController.exec_handle_event(pad_ref, %Events.EndOfStream{}, state)
    else
      {:ok, state}
    end
  end

  @spec remove_pad_associations(Pad.ref_t(), State.t()) :: State.t()
  def remove_pad_associations(pad_ref, state) do
    case PadModel.get_data!(state, pad_ref) do
      %{mode: :pull, demand_mode: :auto} = pad_data ->
        state =
          Enum.reduce(pad_data.associated_pads, state, fn pad, state ->
            PadModel.update_data!(state, pad, :associated_pads, &List.delete(&1, pad_data.ref))
          end)
          |> PadModel.set_data!(pad_ref, :associated_pads, [])

        if pad_data.direction == :output do
          Enum.reduce(
            pad_data.associated_pads,
            state,
            &DemandController.send_auto_demand_if_needed/2
          )
        else
          state
        end

      _pad_data ->
        state
    end
  end

  @spec handle_pad_added(Pad.ref_t(), Core.Element.State.t()) ::
          Type.stateful_try_t(Core.Element.State.t())
  defp handle_pad_added(ref, state) do
    %{options: pad_opts, direction: direction} = PadModel.get_data!(state, ref)
    context = &CallbackContext.PadAdded.from_state(&1, options: pad_opts, direction: direction)

    CallbackHandler.exec_and_handle_callback(
      :handle_pad_added,
      ActionHandler,
      %{context: context},
      [ref],
      state
    )
  end

  @spec handle_pad_removed(Pad.ref_t(), Core.Element.State.t()) ::
          Type.stateful_try_t(Core.Element.State.t())
  def handle_pad_removed(ref, state) do
    %{direction: direction, availability: availability} = PadModel.get_data!(state, ref)
    context = &CallbackContext.PadRemoved.from_state(&1, direction: direction)

    if Pad.availability_mode(availability) == :dynamic do
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
