defmodule Membrane.Core.Element.PadController do
  @moduledoc false

  # Module handling linking and unlinking pads.

  use Bunch
  alias Membrane.Core.{CallbackHandler, Child, Events}

  alias Membrane.Core.Element.{
    ActionHandler,
    AtomicDemand,
    CallbackContext,
    EffectiveFlowController,
    EventController,
    InputQueue,
    State,
    StreamFormatController
  }

  alias Membrane.Core.Element.DemandController.AutoFlowUtils
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.LinkError

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Core.Message, as: Message
  require Membrane.Core.Stalker, as: Stalker
  require Membrane.Logger
  require Membrane.Pad, as: Pad

  @type link_call_props ::
          %{
            stream_format_validation_params:
              StreamFormatController.stream_format_validation_params()
          }
          | %{
              other_info: PadModel.pad_info() | nil,
              link_metadata: %{},
              stream_format_validation_params:
                StreamFormatController.stream_format_validation_params(),
              other_effective_flow_control: EffectiveFlowController.effective_flow_control()
            }

  @type link_call_reply_props ::
          {Endpoint.t(), PadModel.pad_info(), %{atomic_demand: AtomicDemand.t()}}

  @type link_call_reply ::
          :ok
          | {:ok, link_call_reply_props}
          | {:error, {:neighbor_dead, reason :: any()}}
          | {:error, {:neighbor_child_dead, reason :: any()}}
          | {:error, {:unknown_pad, name :: Membrane.Child.name(), pad_ref :: Pad.ref()}}

  @default_auto_demand_size_factor 400

  @doc """
  Verifies linked pad, initializes it's data.
  """
  @spec handle_link(Pad.direction(), Endpoint.t(), Endpoint.t(), link_call_props, State.t()) ::
          {link_call_reply, State.t()}
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

    do_handle_link(direction, endpoint, other_endpoint, info, link_props, state)
  end

  defp do_handle_link(:output, endpoint, other_endpoint, info, props, state) do
    effective_flow_control =
      EffectiveFlowController.get_pad_effective_flow_control(endpoint.pad_ref, state)

    handle_link_response =
      Message.call(other_endpoint.pid, :handle_link, [
        Pad.opposite_direction(info.direction),
        other_endpoint,
        endpoint,
        %{
          other_info: info,
          link_metadata: %{
            observability_data: Stalker.generate_observability_data_for_link(endpoint.pad_ref)
          },
          stream_format_validation_params: [],
          other_effective_flow_control: effective_flow_control
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
            :push,
            other_info,
            link_metadata,
            state
          )

        state = maybe_handle_pad_added(endpoint.pad_ref, state)
        {:ok, state}

      {:error, {:call_failure, reason}} ->
        Membrane.Logger.debug("""
        Tried to link pad #{inspect(endpoint.pad_ref)}, but neighbour #{inspect(other_endpoint.child)}
        is not alive.
        """)

        {{:error, {:neighbor_dead, reason}}, state}

      {:error, {:unknown_pad, _name, _pad_ref}} = error ->
        {error, state}

      {:error, {:child_dead, reason}} ->
        {{:error, {:neighbor_child_dead, reason}}, state}
    end
  end

  defp do_handle_link(:input, endpoint, other_endpoint, info, link_props, state) do
    %{
      other_info: other_info,
      link_metadata: link_metadata,
      stream_format_validation_params: stream_format_validation_params,
      other_effective_flow_control: other_effective_flow_control
    } = link_props

    if info.direction != :input, do: raise("pad direction #{inspect(info.direction)} is wrong")

    {output_demand_unit, input_demand_unit} = resolve_demand_units(other_info, info)

    link_metadata =
      Map.merge(link_metadata, %{
        input_demand_unit: input_demand_unit,
        output_demand_unit: output_demand_unit
      })

    pad_effective_flow_control =
      EffectiveFlowController.get_pad_effective_flow_control(endpoint.pad_ref, state)

    atomic_demand =
      AtomicDemand.new(%{
        receiver_effective_flow_control: pad_effective_flow_control,
        receiver_process: self(),
        receiver_demand_unit: input_demand_unit || :buffers,
        sender_process: other_endpoint.pid,
        sender_pad_ref: other_endpoint.pad_ref,
        supervisor: state.subprocess_supervisor,
        toilet_capacity: endpoint.pad_props[:toilet_capacity],
        throttling_factor: endpoint.pad_props[:throttling_factor]
      })

    Stalker.register_link(
      state.stalker,
      endpoint.pad_ref,
      other_endpoint.pad_ref,
      link_metadata.observability_data
    )

    link_metadata = Map.put(link_metadata, :atomic_demand, atomic_demand)

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
        other_effective_flow_control,
        other_info,
        link_metadata,
        state
      )

    state =
      case PadModel.get_data!(state, endpoint.pad_ref) do
        %{flow_control: :auto, direction: :input} = pad_data ->
          EffectiveFlowController.handle_sender_effective_flow_control(
            pad_data.ref,
            pad_data.other_effective_flow_control,
            state
          )

        _pad_data ->
          state
      end

    state = maybe_handle_pad_added(endpoint.pad_ref, state)

    link_metadata = %{
      link_metadata
      | observability_data:
          Stalker.generate_observability_data_for_link(
            endpoint.pad_ref,
            link_metadata.observability_data
          )
    }

    {{:ok, {endpoint, info, link_metadata}}, state}
  end

  @doc """
  Handles situation where pad has been unlinked (e.g. when connected element has been removed from pipeline)

  Removes pad data.
  Signals an EoS (via handle_event) to the element if unlinked pad was an input.
  Executes `handle_pad_removed` callback if the pad was dynamic.
  Note: it also flushes all buffers from PlaybackBuffer.
  """
  @spec handle_unlink(Pad.ref(), State.t()) :: State.t()
  def handle_unlink(pad_ref, state) do
    with {:ok, %{availability: :on_request}} <- PadModel.get_data(state, pad_ref) do
      Stalker.unregister_link(state.stalker, pad_ref)
      state = generate_eos_if_needed(pad_ref, state)
      state = maybe_handle_pad_removed(pad_ref, state)
      state = remove_pad_associations(pad_ref, state)
      {pad_data, state} = PadModel.pop_data!(state, pad_ref)

      with %{direction: :input, flow_control: :auto, other_effective_flow_control: :pull} <-
             pad_data do
        EffectiveFlowController.resolve_effective_flow_control(state)
      else
        _pad_data -> state
      end
    else
      {:ok, %{availability: :always}} when state.terminating? ->
        state

      {:ok, %{availability: :always}} ->
        raise Membrane.PadError,
              "Tried to unlink a static pad #{inspect(pad_ref)}. Static pads cannot be unlinked unless element is terminating"

      {:error, :unknown_pad} ->
        with false <- state.terminating?,
             %{availability: :always} <- state.pads_info[Pad.name_by_ref(pad_ref)] do
          raise Membrane.PadError,
                "Tried to unlink a static pad #{inspect(pad_ref)}, before it was linked. Static pads cannot be unlinked unless element is terminating"
        end

        Membrane.Logger.debug(
          "Ignoring unlinking pad #{inspect(pad_ref)} that hasn't been successfully linked"
        )

        state
    end
  end

  defp resolve_demand_units(output_info, input_info) do
    output_demand_unit = output_info[:demand_unit] || input_info[:demand_unit] || :buffers
    input_demand_unit = input_info[:demand_unit] || output_info[:demand_unit] || :buffers

    {output_demand_unit, input_demand_unit}
  end

  defp init_pad_data(
         endpoint,
         other_endpoint,
         info,
         stream_format_validation_params,
         other_effective_flow_control,
         other_info,
         metadata,
         state
       ) do
    total_buffers_metric = :atomics.new(1, [])

    Membrane.Core.Stalker.register_metric_function(
      :total_buffers,
      fn -> :atomics.get(total_buffers_metric, 1) end,
      pad: endpoint.pad_ref
    )

    Membrane.Core.Stalker.register_metric_function(
      :atomic_demand,
      fn -> AtomicDemand.get(metadata.atomic_demand) end,
      pad: endpoint.pad_ref
    )

    data =
      info
      |> Map.delete(:accepted_formats_str)
      |> merge_pad_data(
        &%{
          pid: other_endpoint.pid,
          other_ref: other_endpoint.pad_ref,
          options:
            Child.PadController.parse_pad_options!(&1.name, endpoint.pad_props.options, state),
          ref: endpoint.pad_ref,
          stream_format_validation_params: stream_format_validation_params,
          other_effective_flow_control: other_effective_flow_control,
          stream_format: nil,
          start_of_stream?: false,
          end_of_stream?: false,
          associated_pads: [],
          atomic_demand: metadata.atomic_demand,
          stalker_metrics: %{
            total_buffers: total_buffers_metric
          }
        }
      )
      |> merge_pad_data(&init_pad_direction_data(&1, endpoint.pad_props, metadata, state))
      |> merge_pad_data(&init_pad_mode_data(&1, endpoint.pad_props, other_info, metadata, state))
      |> then(&struct!(Membrane.Element.PadData, &1))

    state = put_in(state, [:pads_data, endpoint.pad_ref], data)

    :ok =
      AtomicDemand.set_sender_status(
        data.atomic_demand,
        {:resolved, EffectiveFlowController.get_pad_effective_flow_control(data.ref, state)}
      )

    if data.flow_control == :auto do
      state =
        state.pads_data
        |> Map.values()
        |> Enum.filter(&(&1.direction != data.direction and &1.flow_control == :auto))
        |> Enum.reduce(state, fn other_data, state ->
          PadModel.update_data!(state, other_data.ref, :associated_pads, &[data.ref | &1])
        end)

      if data.direction == :input,
        do: AutoFlowUtils.auto_adjust_atomic_demand(endpoint.pad_ref, state),
        else: state
    else
      state
    end
  end

  defp merge_pad_data(pad_data, fun) do
    Map.merge(pad_data, fun.(pad_data), fn
      :stalker_metrics, m1, m2 -> Map.merge(m1, m2)
      _key, _v1, v2 -> v2
    end)
  end

  defp init_pad_direction_data(%{direction: :input}, _props, metadata, _state),
    do: %{
      sticky_messages: [],
      demand_unit: metadata.input_demand_unit,
      other_demand_unit: metadata.output_demand_unit
    }

  defp init_pad_direction_data(%{direction: :output}, _props, metadata, _state),
    do: %{demand_unit: metadata.output_demand_unit, other_demand_unit: metadata.input_demand_unit}

  defp init_pad_mode_data(
         %{direction: :input, flow_control: :manual} = data,
         props,
         other_info,
         _metadata,
         %State{}
       ) do
    %{
      ref: ref,
      demand_unit: this_demand_unit,
      atomic_demand: atomic_demand
    } = data

    input_queue =
      InputQueue.init(%{
        inbound_demand_unit: other_info[:demand_unit] || this_demand_unit,
        outbound_demand_unit: this_demand_unit,
        atomic_demand: atomic_demand,
        pad_ref: ref,
        log_tag: inspect(ref),
        target_size: props.target_queue_size
      })

    %{input_queue: input_queue, demand: 0}
  end

  defp init_pad_mode_data(
         %{direction: :output, flow_control: :manual},
         _props,
         _other_info,
         _metadata,
         _state
       ) do
    %{demand: 0}
  end

  defp init_pad_mode_data(
         %{flow_control: :auto, direction: direction} = data,
         props,
         _other_info,
         _metadata,
         %State{} = state
       ) do
    associated_pads =
      state.pads_data
      |> Map.values()
      |> Enum.filter(&(&1.direction != direction and &1.flow_control == :auto))
      |> Enum.map(& &1.ref)

    auto_demand_size =
      cond do
        direction == :output ->
          nil

        props.auto_demand_size != nil ->
          props.auto_demand_size

        true ->
          demand_unit = data.other_demand_unit || data.demand_unit || :buffers
          metric = Membrane.Buffer.Metric.from_unit(demand_unit)
          metric.buffer_size_approximation() * @default_auto_demand_size_factor
      end

    demand_metric =
      if direction == :input do
        :atomics.new(1, [])
        |> tap(
          &Stalker.register_metric_function(:auto_demand_size, fn -> :atomics.get(&1, 1) end,
            pad: data.ref
          )
        )
      end

    %{
      demand: 0,
      associated_pads: associated_pads,
      auto_demand_size: auto_demand_size,
      stalker_metrics: %{demand: demand_metric}
    }
  end

  defp init_pad_mode_data(_data, _props, _other_info, _metadata, _state), do: %{}

  @doc """
  Generates end of stream on the given input pad if it hasn't been generated yet
  and playback is `playing`.
  """
  @spec generate_eos_if_needed(Pad.ref(), State.t()) :: State.t()
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
  @spec remove_pad_associations(Pad.ref(), State.t()) :: State.t()
  def remove_pad_associations(pad_ref, state) do
    case PadModel.get_data!(state, pad_ref) do
      %{flow_control: :auto} = pad_data ->
        state =
          Enum.reduce(pad_data.associated_pads, state, fn pad, state ->
            PadModel.update_data!(state, pad, :associated_pads, &List.delete(&1, pad_data.ref))
          end)
          |> PadModel.set_data!(pad_ref, :associated_pads, [])

        if pad_data.direction == :output,
          do: AutoFlowUtils.auto_adjust_atomic_demand(pad_data.associated_pads, state),
          else: state

      _pad_data ->
        state
    end
  end

  @spec maybe_handle_pad_added(Pad.ref(), State.t()) :: State.t()
  defp maybe_handle_pad_added(ref, state) do
    %{options: pad_opts, availability: availability} = PadModel.get_data!(state, ref)

    if Pad.availability_mode(availability) == :dynamic do
      context = &CallbackContext.from_state(&1, options: pad_opts)

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

  @spec maybe_handle_pad_removed(Pad.ref(), State.t()) :: State.t()
  defp maybe_handle_pad_removed(ref, state) do
    %{availability: availability} = PadModel.get_data!(state, ref)

    if Pad.availability_mode(availability) == :dynamic do
      CallbackHandler.exec_and_handle_callback(
        :handle_pad_removed,
        ActionHandler,
        %{context: &CallbackContext.from_state/1},
        [ref],
        state
      )
    else
      state
    end
  end
end
