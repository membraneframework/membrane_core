defmodule Membrane.Core.Element.PadController do
  @moduledoc false

  # Module handling linking and unlinking pads.

  use Bunch
  alias Membrane.{LinkError, Pad}
  alias Membrane.Core.{CallbackHandler, Child, Events, Message, Observability}
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    ActionHandler,
    DemandController,
    EventController,
    InputQueue,
    State,
    StreamFormatController,
    Toilet
  }

  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.Element.CallbackContext

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Element.CallbackContext.{PadAdded, PadRemoved}
  require Membrane.Logger
  require Membrane.Pad

  @type link_call_props_t ::
          %{
            initiator: :parent,
            stream_format_validation_params:
              StreamFormatController.stream_format_validation_params_t()
          }
          | %{
              initiator: :sibling,
              other_info: PadModel.pad_info_t() | nil,
              link_metadata: %{toilet: Toilet.t() | nil},
              stream_format_validation_params:
                StreamFormatController.stream_format_validation_params_t()
            }

  @type link_call_reply_props_t ::
          {Endpoint.t(), PadModel.pad_info_t(), %{toilet: Toilet.t() | nil}}

  @type link_call_reply_t ::
          :ok | {:ok, link_call_reply_props_t} | {:error, {:neighbor_dead, reason :: any}}

  @default_auto_demand_size_factor 4000

  @doc """
  Verifies linked pad, initializes it's data.
  """
  @spec handle_link(Pad.direction_t(), Endpoint.t(), Endpoint.t(), link_call_props_t, State.t()) ::
          {link_call_reply_t, State.t()}
  def handle_link(direction, endpoint, other_endpoint, link_props, state) do
    Membrane.Logger.debug(
      "Element handle link on pad #{inspect(endpoint.pad_ref)} with pad #{inspect(other_endpoint.pad_ref)} of child #{inspect(other_endpoint.child)}"
    )

    name = endpoint.pad_ref |> Pad.name_by_ref()

    info =
      case Map.fetch(state.pads_info, name) do
        {:ok, info} ->
          info

        :error ->
          raise LinkError,
                "Tried to link via unknown pad #{inspect(name)} of #{inspect(state.name)}"
      end

    :ok = Child.PadController.validate_pad_being_linked!(direction, info)

    toilet =
      if direction == :input and info.mode == :pull do
        Toilet.new(
          endpoint.pad_props.toilet_capacity,
          info.demand_unit,
          self(),
          endpoint.pad_props.throttling_factor
        )
      else
        nil
      end

    do_handle_link(endpoint, other_endpoint, info, toilet, link_props, state)
  end

  defp do_handle_link(
         endpoint,
         other_endpoint,
         info,
         toilet,
         %{initiator: :parent} = props,
         state
       ) do
    handle_link_response =
      Message.call(other_endpoint.pid, :handle_link, [
        Pad.opposite_direction(info.direction),
        other_endpoint,
        endpoint,
        %{
          initiator: :sibling,
          other_info: info,
          link_metadata: %{
            toilet: toilet,
            observability_metadata: Observability.setup_link(endpoint.pad_ref)
          },
          stream_format_validation_params: []
        }
      ])

    case handle_link_response do
      {:ok, {other_endpoint, other_info, link_metadata}} ->
        :ok =
          Child.PadController.validate_pad_mode!(
            {endpoint.pad_ref, info},
            {other_endpoint.pad_ref, other_info}
          )

        state =
          init_pad_data(
            endpoint,
            other_endpoint,
            info,
            props.stream_format_validation_params,
            other_info,
            link_metadata,
            state
          )

        state = maybe_handle_pad_added(endpoint.pad_ref, state)
        {:ok, state}

      {:error, {:call_failure, reason}} ->
        {{:error, {:neighbor_dead, reason}}, state}
    end
  end

  defp do_handle_link(
         endpoint,
         other_endpoint,
         info,
         toilet,
         %{initiator: :sibling} = link_props,
         state
       ) do
    %{
      other_info: other_info,
      link_metadata: link_metadata,
      stream_format_validation_params: stream_format_validation_params
    } = link_props

    Observability.setup_link(endpoint.pad_ref, link_metadata.observability_metadata)
    link_metadata = %{link_metadata | toilet: link_metadata.toilet || toilet}

    :ok =
      Child.PadController.validate_pad_mode!(
        {endpoint.pad_ref, info},
        {other_endpoint.pad_ref, other_info}
      )

    state =
      init_pad_data(
        endpoint,
        other_endpoint,
        info,
        stream_format_validation_params,
        other_info,
        link_metadata,
        state
      )

    state = maybe_handle_pad_added(endpoint.pad_ref, state)
    {{:ok, {endpoint, info, link_metadata}}, state}
  end

  @doc """
  Handles situation where pad has been unlinked (e.g. when connected element has been removed from pipeline)

  Removes pad data.
  Signals an EoS (via handle_event) to the element if unlinked pad was an input.
  Executes `handle_pad_removed` callback if the pad was dynamic.
  Note: it also flushes all buffers from PlaybackBuffer.
  """
  @spec handle_unlink(Pad.ref_t(), State.t()) :: State.t()
  def handle_unlink(pad_ref, state) do
    with {:ok, %{availability: :on_request}} <- PadModel.get_data(state, pad_ref) do
      state = generate_eos_if_needed(pad_ref, state)
      state = maybe_handle_pad_removed(pad_ref, state)
      state = remove_pad_associations(pad_ref, state)
      PadModel.delete_data!(state, pad_ref)
    else
      {:ok, %{availability: :always}} when state.terminating? ->
        state

      {:ok, %{availability: :always}} ->
        raise Membrane.PadError,
              "Tried to unlink a static pad #{inspect(pad_ref)}. Static pads cannot be unlinked unless element is terminating"

      {:error, :unknown_pad} ->
        Membrane.Logger.debug(
          "Ignoring unlinking pad #{inspect(pad_ref)} that hasn't been successfully linked"
        )

        state
    end
  end

  defp init_pad_data(
         endpoint,
         other_endpoint,
         info,
         stream_format_validation_params,
         other_info,
         metadata,
         state
       ) do
    data =
      info
      |> Map.delete(:accepted_formats_str)
      |> Map.merge(%{
        pid: other_endpoint.pid,
        other_ref: other_endpoint.pad_ref,
        options:
          Child.PadController.parse_pad_options!(info.name, endpoint.pad_props.options, state),
        ref: endpoint.pad_ref,
        stream_format_validation_params: stream_format_validation_params,
        stream_format: nil,
        start_of_stream?: false,
        end_of_stream?: false,
        associated_pads: []
      })

    data = data |> Map.merge(init_pad_direction_data(data, endpoint.pad_props, state))

    data =
      data |> Map.merge(init_pad_mode_data(data, endpoint.pad_props, other_info, metadata, state))

    data = struct!(Membrane.Element.PadData, data)
    state = put_in(state, [:pads_data, endpoint.pad_ref], data)

    if data.demand_mode == :auto do
      state =
        state.pads_data
        |> Map.values()
        |> Enum.filter(&(&1.direction != data.direction and &1.demand_mode == :auto))
        |> Enum.reduce(state, fn other_data, state ->
          PadModel.update_data!(state, other_data.ref, :associated_pads, &[data.ref | &1])
        end)

      case data.direction do
        :input -> DemandController.send_auto_demand_if_needed(endpoint.pad_ref, state)
        :output -> state
      end
    else
      state
    end
  end

  defp init_pad_direction_data(%{direction: :input}, _props, _state), do: %{sticky_messages: []}
  defp init_pad_direction_data(%{direction: :output}, _props, _state), do: %{}

  defp init_pad_mode_data(
         %{mode: :pull, direction: :input, demand_mode: :manual} = data,
         props,
         other_info,
         metadata,
         %State{}
       ) do
    %{ref: ref, pid: pid, other_ref: other_ref, demand_unit: demand_unit} = data
    enable_toilet? = other_info.mode == :push

    input_queue =
      InputQueue.init(%{
        demand_unit: demand_unit,
        demand_pid: pid,
        demand_pad: other_ref,
        log_tag: inspect(ref),
        toilet?: enable_toilet?,
        target_size: props.target_queue_size,
        min_demand_factor: props.min_demand_factor
      })

    %{input_queue: input_queue, demand: 0, toilet: if(enable_toilet?, do: metadata.toilet)}
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
         props,
         other_info,
         metadata,
         %State{} = state
       ) do
    associated_pads =
      state.pads_data
      |> Map.values()
      |> Enum.filter(&(&1.direction != direction and &1.demand_mode == :auto))
      |> Enum.map(& &1.ref)

    toilet =
      if direction == :input and other_info.mode == :push do
        metadata.toilet
      else
        nil
      end

    auto_demand_size =
      if direction == :input do
        props.auto_demand_size ||
          Membrane.Buffer.Metric.Count.buffer_size_approximation() *
            @default_auto_demand_size_factor
      else
        nil
      end

    %{
      demand: 0,
      associated_pads: associated_pads,
      other_demand_unit: other_info[:demand_unit],
      auto_demand_size: auto_demand_size,
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

  @doc """
  Generates end of stream on the given input pad if it hasn't been generated yet
  and playback is `playing`.
  """
  @spec generate_eos_if_needed(Pad.ref_t(), State.t()) :: State.t()
  def generate_eos_if_needed(pad_ref, state) do
    %{direction: direction, end_of_stream?: eos?} = PadModel.get_data!(state, pad_ref)

    if direction == :input and not eos? and state.playback == :playing do
      EventController.exec_handle_event(pad_ref, %Events.EndOfStream{}, state)
    else
      state
    end
  end

  @doc """
  Removes all associations between the given pad and any other_endpoint pads.
  """
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

  @spec maybe_handle_pad_added(Pad.ref_t(), State.t()) :: State.t()
  defp maybe_handle_pad_added(ref, state) do
    %{options: pad_opts, direction: direction, availability: availability} =
      PadModel.get_data!(state, ref)

    if Pad.availability_mode(availability) == :dynamic do
      context = &CallbackContext.PadAdded.from_state(&1, options: pad_opts, direction: direction)

      CallbackHandler.exec_and_handle_callback(
        :handle_pad_added,
        ActionHandler,
        %{context: context},
        [ref],
        state
      )
    else
      state
    end
  end

  @spec maybe_handle_pad_removed(Pad.ref_t(), State.t()) :: State.t()
  defp maybe_handle_pad_removed(ref, state) do
    %{direction: direction, availability: availability} = PadModel.get_data!(state, ref)

    if Pad.availability_mode(availability) == :dynamic do
      context = &CallbackContext.PadRemoved.from_state(&1, direction: direction)

      CallbackHandler.exec_and_handle_callback(
        :handle_pad_removed,
        ActionHandler,
        %{context: context},
        [ref],
        state
      )
    else
      state
    end
  end
end
