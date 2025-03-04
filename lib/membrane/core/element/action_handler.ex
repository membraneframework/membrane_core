defmodule Membrane.Core.Element.ActionHandler do
  @moduledoc false

  # Module validating and executing actions returned by element's callbacks.

  use Bunch
  use Membrane.Core.CallbackHandler

  import Membrane.Pad, only: [is_pad_ref: 1]

  alias Membrane.{
    ActionError,
    Buffer,
    Core,
    ElementError,
    Event,
    Pad,
    PadDirectionError,
    StreamFormat
  }

  alias Membrane.Core.Element.{
    AutoFlowController,
    DemandController,
    ManualFlowController,
    State,
    StreamFormatController
  }

  alias Membrane.Core.{Events, TimerController}
  alias Membrane.Element.Action

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Core.Message, as: Message
  require Membrane.Logger
  require Membrane.Core.Telemetry, as: Telemetry
  require Membrane.Core.LegacyTelemetry, as: LegacyTelemetry

  @impl CallbackHandler
  def transform_actions(actions, _callback, _handler_params, state) do
    actions = join_buffers(actions)
    {actions, state}
  end

  defguardp is_demand_size(size) when is_integer(size) or is_function(size)

  @impl CallbackHandler
  def handle_end_of_actions(state) do
    # Fixed order of handling demand of manual and auto pads would lead to
    # favoring manual pads over auto pads (or vice versa), especially after
    # introducting auto flow queues.

    if Enum.random([true, false]) do
      state
      |> handle_pads_to_snapshot()
      |> maybe_handle_delayed_demands()
    else
      state
      |> maybe_handle_delayed_demands()
      |> handle_pads_to_snapshot()
    end
  end

  defp maybe_handle_delayed_demands(state) do
    with %{delay_demands?: false} <- state do
      ManualFlowController.handle_delayed_demands(state)
    end
  end

  defp handle_pads_to_snapshot(state) do
    state.pads_to_snapshot
    |> Enum.shuffle()
    |> Enum.reduce(state, &DemandController.snapshot_atomic_demand/2)
    |> Map.put(:pads_to_snapshot, MapSet.new())
  end

  @impl CallbackHandler
  def handle_action({action, _}, :handle_init, _params, _state)
      when action not in [:latency, :notify_parent] do
    raise ActionError, action: action, reason: {:invalid_callback, :handle_init}
  end

  @impl CallbackHandler
  def handle_action({action, _}, _cb, _params, %State{playback: playback})
      when playback != :playing and
             action in [
               :buffer,
               :event,
               :stream_format,
               :demand,
               :redemand,
               :pause_auto_demand,
               :resume_auto_demand,
               :forward,
               :end_of_stream
             ] do
    raise ActionError, action: action, reason: {:invalid_component_playback, playback}
  end

  @impl CallbackHandler
  def handle_action({:setup, :incomplete} = action, cb, _params, _state)
      when cb != :handle_setup do
    raise ActionError, action: action, reason: {:invalid_callback, :handle_setup}
  end

  @impl CallbackHandler
  def handle_action({:setup, operation}, _cb, _params, state) do
    Core.LifecycleController.handle_setup_operation(operation, state)
  end

  @impl CallbackHandler
  def handle_action({:event, {pad_ref, event}}, _cb, _params, state)
      when is_pad_ref(pad_ref) do
    send_event(pad_ref, event, state)
  end

  @impl CallbackHandler
  def handle_action({:notify_parent, notification}, _cb, _params, state) do
    %State{name: name, parent_pid: parent_pid} = state

    Membrane.Logger.debug_verbose(
      "Sending notification #{inspect(notification)} (parent PID: #{inspect(parent_pid)})"
    )

    Message.send(parent_pid, :child_notification, [name, notification])
    state
  end

  @impl CallbackHandler
  def handle_action({:split, {callback, args_list}}, cb, params, state) do
    CallbackHandler.exec_and_handle_split_callback(
      callback,
      cb,
      __MODULE__,
      params,
      args_list,
      state
    )
  end

  @impl CallbackHandler
  def handle_action({:buffer, {pad_ref, buffers}}, _cb, _params, %State{type: type} = state)
      when type in [:source, :filter, :endpoint] and is_pad_ref(pad_ref) do
    send_buffer(pad_ref, buffers, state)
  end

  @impl CallbackHandler
  def handle_action(
        {:stream_format, {pad_ref, stream_format}},
        _cb,
        _params,
        %State{type: type} = state
      )
      when type in [:source, :filter, :endpoint] and is_pad_ref(pad_ref) do
    send_stream_format(pad_ref, stream_format, state)
  end

  @impl CallbackHandler
  def handle_action({action, pads_refs}, cb, params, state)
      when action in [:redemand, :pause_auto_demand, :resume_auto_demand] and is_list(pads_refs) do
    Enum.reduce(pads_refs, state, fn pad_ref, state ->
      handle_action({action, pad_ref}, cb, params, state)
    end)
  end

  @impl CallbackHandler
  def handle_action({:redemand, out_ref}, cb, _params, %State{type: type} = state)
      when type in [:source, :filter, :endpoint] and {type, cb} != {:filter, :handle_demand} do
    handle_redemand(out_ref, state)
  end

  @impl CallbackHandler
  def handle_action({:pause_auto_demand, in_ref}, _cb, _params, %State{type: type} = state)
      when type in [:sink, :filter, :endpoint] do
    AutoFlowController.pause_demands(in_ref, state)
  end

  @impl CallbackHandler
  def handle_action({:resume_auto_demand, in_ref}, _cb, _params, %State{type: type} = state)
      when type in [:sink, :filter, :endpoint] do
    AutoFlowController.resume_demands(in_ref, state)
  end

  @impl CallbackHandler
  def handle_action({:forward, data}, cb, params, %State{type: :filter} = state)
      when cb in [
             :handle_stream_format,
             :handle_event,
             :handle_buffer,
             :handle_end_of_stream
           ] do
    dir =
      case cb do
        :handle_event -> Pad.opposite_direction(params.direction)
        _other -> :output
      end

    pads =
      Enum.flat_map(state.pads_data, fn
        {pad_ref, %{direction: ^dir}} -> [pad_ref]
        _pad_entry -> []
      end)

    Enum.reduce(pads, state, fn pad, state ->
      action =
        case cb do
          :handle_event -> {:event, {pad, data}}
          :handle_buffer -> {:buffer, {pad, data}}
          :handle_stream_format -> {:stream_format, {pad, data}}
          :handle_end_of_stream -> {:end_of_stream, pad}
        end

      handle_action(action, cb, params, state)
    end)
  end

  @impl CallbackHandler
  def handle_action(
        {:demand, pad_ref},
        cb,
        params,
        %State{type: type} = state
      )
      when is_pad_ref(pad_ref) and type in [:sink, :filter, :endpoint] do
    handle_action({:demand, {pad_ref, 1}}, cb, params, state)
  end

  @impl CallbackHandler
  def handle_action(
        {:demand, {pad_ref, size}},
        cb,
        _params,
        %State{type: type} = state
      )
      when is_pad_ref(pad_ref) and is_demand_size(size) and type in [:sink, :filter, :endpoint] do
    :ok = maybe_warn_on_demand_action(pad_ref, size, cb, state)
    delay_supplying_demand(pad_ref, size, state)
  end

  @impl CallbackHandler
  def handle_action({:start_timer, {id, interval, clock}}, _cb, _params, state) do
    TimerController.start_timer(id, interval, clock, state)
  end

  @impl CallbackHandler
  def handle_action({:start_timer, {id, interval}}, cb, params, state) do
    clock = state.synchronization.parent_clock
    handle_action({:start_timer, {id, interval, clock}}, cb, params, state)
  end

  @impl CallbackHandler
  def handle_action({:timer_interval, {id, interval}}, cb, _params, state)
      when interval != :no_interval or cb == :handle_tick do
    TimerController.timer_interval(id, interval, state)
  end

  @impl CallbackHandler
  def handle_action({:stop_timer, id}, _cb, _params, state) do
    TimerController.stop_timer(id, state)
  end

  @impl CallbackHandler
  def handle_action({:latency, latency}, _cb, _params, state) do
    put_in(state.synchronization.latency, latency)
  end

  @impl CallbackHandler
  def handle_action({:end_of_stream, pad_ref}, _callback, _params, %State{type: type} = state)
      when is_pad_ref(pad_ref) and type != :sink do
    send_event(pad_ref, %Events.EndOfStream{}, state)
  end

  @impl CallbackHandler
  def handle_action({:terminate, :normal}, _cb, _params, %State{terminating?: false}) do
    raise Membrane.ElementError,
          "Cannot terminate an element with reason `:normal` unless it's removed by its parent"
  end

  @impl CallbackHandler
  def handle_action({:terminate, reason}, _cb, _params, _state) do
    Membrane.Logger.debug("Terminating with reason #{inspect(reason)}")
    exit(reason)
  end

  @impl CallbackHandler
  def handle_action(action, _callback, _params, _state) do
    raise ActionError, action: action, reason: {:unknown_action, Membrane.Element.Action}
  end

  defp join_buffers(actions) do
    actions
    |> Bunch.Enum.chunk_by_prev(
      fn
        {:buffer, {pad, _}}, {:buffer, {pad, _}} -> true
        _prev_action, _action -> false
      end,
      fn
        [{:buffer, {pad, _}} | _] = buffers ->
          {:buffer, {pad, buffers |> Enum.map(fn {_, {_, b}} -> [b] end) |> List.flatten()}}

        [other] ->
          other
      end
    )
  end

  @spec send_buffer(Pad.ref(), [Buffer.t()] | Buffer.t(), State.t()) :: State.t()
  defp send_buffer(_pad_ref, [], state) do
    state
  end

  defp send_buffer(pad_ref, %Buffer{} = buffer, state) do
    send_buffer(pad_ref, [buffer], state)
  end

  defp send_buffer(pad_ref, buffers, state) when is_list(buffers) do
    Membrane.Logger.debug_verbose(
      "Sending #{length(buffers)} buffer(s) through pad #{inspect(pad_ref)}"
    )

    LegacyTelemetry.report_bitrate(buffers)
    Telemetry.report_buffer(buffers)

    Enum.each(buffers, fn
      %Buffer{} -> :ok
      value -> raise ElementError, "Tried to send an invalid buffer #{inspect(value)}"
    end)

    pad_data = PadModel.get_data!(state, pad_ref)

    with %{
           direction: :output,
           end_of_stream?: false,
           stream_format: stream_format,
           pid: pid,
           other_ref: other_ref,
           stalker_metrics: stalker_metrics
         }
         when stream_format != nil <- pad_data do
      state = DemandController.decrease_demand_by_outgoing_buffers(pad_ref, buffers, state)
      :atomics.add(stalker_metrics.total_buffers, 1, length(buffers))
      Message.send(pid, :buffer, buffers, for_pad: other_ref)

      PadModel.set_data!(state, pad_ref, :start_of_stream?, true)
      |> Map.update!(:pads_to_snapshot, &MapSet.put(&1, pad_ref))
    else
      %{direction: :input} ->
        raise PadDirectionError, action: :buffer, direction: :input, pad: pad_ref

      %{end_of_stream?: true} ->
        raise ElementError,
              "Tried to send a buffer through a pad #{inspect(pad_ref)} where end of stream has already been sent"

      %{stream_format: nil} ->
        raise ElementError,
              "Tried to send a buffer through a pad #{inspect(pad_ref)} where stream format have not been sent yet"
    end
  end

  defp send_buffer(_pad_ref, invalid_value, _state) do
    raise ElementError, "Tried to send an invalid buffer #{inspect(invalid_value)}"
  end

  @spec send_stream_format(Pad.ref(), StreamFormat.t(), State.t()) :: State.t()
  def send_stream_format(pad_ref, stream_format, state) do
    Membrane.Logger.debug("""
    Sending stream format through pad #{inspect(pad_ref)}
    Stream format: #{inspect(stream_format)}
    """)

    pad_data = PadModel.get_data!(state, pad_ref)

    with %{
           direction: :output,
           pid: pid,
           other_ref: other_ref,
           name: pad_name,
           stream_format_validation_params: validation_params
         } <- pad_data do
      validation_params = [{state.module, pad_name} | validation_params]

      :ok =
        StreamFormatController.validate_stream_format!(:output, validation_params, stream_format)

      state = PadModel.set_data!(state, pad_ref, :stream_format, stream_format)
      Message.send(pid, :stream_format, stream_format, for_pad: other_ref)
      state
    else
      %{direction: :input} ->
        raise PadDirectionError, action: :stream_format, direction: :input, pad: pad_ref
    end
  end

  @spec delay_supplying_demand(
          Pad.ref(),
          Action.demand_size(),
          State.t()
        ) :: State.t()
  defp delay_supplying_demand(pad_ref, 0, state) do
    Membrane.Logger.debug_verbose("Ignoring demand of size of 0 on pad #{inspect(pad_ref)}")
    state
  end

  defp delay_supplying_demand(pad_ref, size, _state)
       when is_integer(size) and size < 0 do
    raise ElementError,
          "Tried to request a negative demand of size #{inspect(size)} on pad #{inspect(pad_ref)}"
  end

  defp delay_supplying_demand(pad_ref, size, state) do
    with %{direction: :input, flow_control: :manual} <-
           PadModel.get_data!(state, pad_ref) do
      state = ManualFlowController.update_demand(pad_ref, size, state)
      ManualFlowController.delay_supplying_demand(pad_ref, state)
    else
      %{direction: :output} ->
        raise PadDirectionError, action: :demand, direction: :output, pad: pad_ref

      %{flow_control: :push} ->
        raise ElementError,
              "Tried to request a demand on pad #{inspect(pad_ref)} working in push flow control mode"

      %{flow_control: :auto} ->
        raise ElementError,
              "Tried to request a demand on pad #{inspect(pad_ref)} that has flow control mode set to auto"
    end
  end

  @spec handle_redemand(Pad.ref(), State.t()) :: State.t()
  defp handle_redemand(pad_ref, %{type: type} = state)
       when type in [:source, :filter, :endpoint] do
    with %{direction: :output, flow_control: :manual} <-
           PadModel.get_data!(state, pad_ref) do
      ManualFlowController.delay_redemand(pad_ref, state)
    else
      %{direction: :input} ->
        raise ElementError, "Tried to make a redemand on input pad #{inspect(pad_ref)}"

      %{flow_control: :push} ->
        raise ElementError,
              "Tried to make a redemand on pad #{inspect(pad_ref)} working in push flow control mode"

      %{flow_control: :auto} ->
        raise ElementError,
              "Tried to make a redemand on pad #{inspect(pad_ref)} that has flow control mode set to auto"
    end
  end

  @spec send_event(Pad.ref(), Event.t(), State.t()) :: State.t()
  defp send_event(pad_ref, event, state) do
    Membrane.Logger.debug_verbose("""
    Sending event through pad #{inspect(pad_ref)}
    Event: #{inspect(event)}
    """)

    if Event.event?(event) do
      %{pid: pid, other_ref: other_ref} = PadModel.get_data!(state, pad_ref)
      state = handle_outgoing_event(pad_ref, event, state)
      Message.send(pid, :event, event, for_pad: other_ref)
      state
    else
      raise Membrane.ElementError,
            "Tried to send invalid event #{inspect(event)} on pad #{inspect(pad_ref)}"
    end
  end

  @spec handle_outgoing_event(Pad.ref(), Event.t(), State.t()) :: State.t()
  defp handle_outgoing_event(pad_ref, %Events.EndOfStream{}, state) do
    with %{direction: :output, end_of_stream?: false} <- PadModel.get_data!(state, pad_ref) do
      ManualFlowController.remove_pad_from_delayed_demands(pad_ref, state)
      |> Map.update!(:satisfied_auto_output_pads, &MapSet.delete(&1, pad_ref))
      |> PadModel.set_data!(pad_ref, :end_of_stream?, true)
      |> AutoFlowController.pop_queues_and_bump_demand()
    else
      %{direction: :input} ->
        raise PadDirectionError, action: "end of stream", direction: :input, pad: pad_ref

      %{end_of_stream?: true} ->
        raise ElementError, "End of stream already set on pad #{inspect(pad_ref)}"
    end
  end

  defp handle_outgoing_event(_pad_ref, _event, state), do: state

  defp maybe_warn_on_demand_action(pad_ref, demand_size, callback, state) do
    if PadModel.get_data!(state, pad_ref, :end_of_stream?) do
      Membrane.Logger.warning("""
      Action :demand with value #{inspect(demand_size)} for pad #{inspect(pad_ref)} was returned \
      from callback #{inspect(callback)}, but stream on this pad has already ended, callback \
      c:handle_end_of_stream/3 for this pad has been called and no more buffers will arrive on \
      this pad.
      """)
    end

    :ok
  end
end
