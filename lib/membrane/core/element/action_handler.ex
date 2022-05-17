defmodule Membrane.Core.Element.ActionHandler do
  @moduledoc false

  # Module validating and executing actions returned by element's callbacks.

  use Bunch
  use Membrane.Core.CallbackHandler

  import Membrane.Pad, only: [is_pad_ref: 1]

  alias Membrane.{ActionError, Buffer, Caps, ElementError, Event, Pad, PadDirectionError}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.{DemandHandler, LifecycleController, PadController, State}
  alias Membrane.Core.{Events, Message, PlaybackHandler, TimerController}
  alias Membrane.Core.Telemetry
  alias Membrane.Element.Action

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Core.Telemetry
  require Membrane.Logger

  @impl CallbackHandler
  def transform_actions(actions, callback, _handler_params, state) do
    actions = join_buffers(actions)
    ensure_nothing_after_redemand(actions, callback, state)
    {actions, state}
  end

  defguardp is_demand_size(size) when is_integer(size) or is_function(size)

  @impl CallbackHandler
  def handle_action({action, _}, :handle_init, _params, _state)
      when action not in [:latency, :notify] do
    raise ActionError, action: action, reason: {:invalid_callback, :handle_init}
  end

  @impl CallbackHandler
  def handle_action({action, _}, cb, _params, %State{playback: %{state: :stopped}})
      when action in [:buffer, :event, :caps, :demand, :redemand, :forward, :end_of_stream] and
             cb != :handle_stopped_to_prepared do
    raise ActionError, action: action, reason: {:invalid_playback_state, :stopped}
  end

  @impl CallbackHandler
  def handle_action({:event, {pad_ref, event}}, _cb, _params, state)
      when is_pad_ref(pad_ref) do
    send_event(pad_ref, event, state)
  end

  @impl CallbackHandler
  def handle_action({:notify, notification}, _cb, _params, state) do
    %State{name: name, parent_pid: parent_pid} = state

    Membrane.Logger.debug_verbose(
      "Sending notification #{inspect(notification)} (parent PID: #{inspect(parent_pid)})"
    )

    Message.send(parent_pid, :notification, [name, notification])
    state
  end

  @impl CallbackHandler
  def handle_action({:split, {callback, args_list}}, cb, params, state) do
    CallbackHandler.exec_and_handle_split_callback(
      callback,
      cb,
      __MODULE__,
      params |> Map.merge(%{skip_invoking_redemands: true}),
      args_list,
      state
    )
  end

  @impl CallbackHandler
  def handle_action({:playback_change, :suspend}, cb, _params, state)
      when cb in [
             :handle_stopped_to_prepared,
             :handle_playing_to_prepared,
             :handle_prepared_to_playing,
             :handle_prepared_to_stopped
           ] do
    {:ok, state} = PlaybackHandler.suspend_playback_change(state)
    state
  end

  @impl CallbackHandler
  def handle_action({:playback_change, :resume}, _cb, _params, state) do
    {:ok, state} = PlaybackHandler.continue_playback_change(LifecycleController, state)
    state
  end

  @impl CallbackHandler
  def handle_action({:buffer, _args} = action, cb, _params, %State{
        playback: %{state: playback_state}
      })
      when playback_state != :playing and cb != :handle_prepared_to_playing do
    raise ActionError, action: action, reason: {:invalid_playback_state, playback_state}
  end

  @impl CallbackHandler
  def handle_action({:buffer, {pad_ref, buffers}}, _cb, _params, %State{type: type} = state)
      when type in [:source, :filter, :endpoint] and is_pad_ref(pad_ref) do
    send_buffer(pad_ref, buffers, state)
  end

  @impl CallbackHandler
  def handle_action({:caps, {pad_ref, caps}}, _cb, _params, %State{type: type} = state)
      when type in [:source, :filter, :endpoint] and is_pad_ref(pad_ref) do
    send_caps(pad_ref, caps, state)
  end

  @impl CallbackHandler
  def handle_action({:redemand, out_refs}, cb, params, state)
      when is_list(out_refs) do
    Enum.reduce(out_refs, state, fn out_ref, state ->
      handle_action({:redemand, out_ref}, cb, params, state)
    end)
  end

  @impl CallbackHandler
  def handle_action({:redemand, out_ref}, cb, _params, %State{type: type} = state)
      when type in [:source, :filter, :endpoint] and is_pad_ref(out_ref) and
             {type, cb} != {:filter, :handle_demand} do
    handle_redemand(out_ref, state)
  end

  @impl CallbackHandler
  def handle_action({:forward, data}, cb, params, %State{type: :filter} = state)
      when cb in [
             :handle_caps,
             :handle_event,
             :handle_process_list,
             :handle_end_of_stream
           ] do
    dir =
      case cb do
        :handle_event -> Pad.opposite_direction(params.direction)
        _other -> :output
      end

    pads = state |> PadModel.filter_data(%{direction: dir}) |> Map.keys()

    Enum.reduce(pads, state, fn pad, state ->
      action =
        case cb do
          :handle_event -> {:event, {pad, data}}
          :handle_process_list -> {:buffer, {pad, data}}
          :handle_caps -> {:caps, {pad, data}}
          :handle_end_of_stream -> {:end_of_stream, pad}
        end

      handle_action(action, cb, params, state)
    end)
  end

  @impl CallbackHandler
  def handle_action(
        {:demand, _args} = action,
        cb,
        _params,
        %State{playback: %{state: playback_state}}
      )
      when playback_state != :playing and cb != :handle_prepared_to_playing do
    raise ActionError, action: action, reason: {:invalid_playback_state, playback_state}
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
        _cb,
        _params,
        %State{type: type} = state
      )
      when is_pad_ref(pad_ref) and is_demand_size(size) and type in [:sink, :filter, :endpoint] do
    supply_demand(pad_ref, size, state)
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
  def handle_action(
        {:end_of_stream, pad_ref},
        _callback,
        _params,
        %State{type: type, playback: %{state: :playing}} = state
      )
      when is_pad_ref(pad_ref) and type != :sink do
    send_event(pad_ref, %Events.EndOfStream{}, state)
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

  defp ensure_nothing_after_redemand(actions, callback, state) do
    {redemands, actions_after_redemands} =
      actions
      |> Enum.drop_while(fn
        {:redemand, _args} -> false
        _other_action -> true
      end)
      |> Enum.split_while(fn
        {:redemand, _args} -> true
        _other_action -> false
      end)

    case {redemands, actions_after_redemands} do
      {_redemands, []} ->
        :ok

      {[redemand | _redemands], _actions_after_redemands} ->
        raise ActionError,
          reason: :actions_after_redemand,
          action: redemand,
          callback: {state.module, callback}
    end
  end

  @spec send_buffer(Pad.ref_t(), [Buffer.t()] | Buffer.t(), State.t()) :: State.t()
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

    Telemetry.report_metric(:buffer, length(buffers))
    Telemetry.report_bitrate(buffers)

    Enum.each(buffers, fn
      %Buffer{} -> :ok
      value -> raise ElementError, "Tried to send an invalid buffer #{inspect(value)}"
    end)

    pad_data = PadModel.get_data!(state, pad_ref)

    with %{
           direction: :output,
           end_of_stream?: false,
           caps: caps,
           pid: pid,
           other_ref: other_ref
         }
         when caps != nil <- pad_data do
      state =
        DemandHandler.handle_outgoing_buffers(pad_ref, pad_data, buffers, state)
        |> PadModel.set_data!(pad_ref, :start_of_stream?, true)

      Message.send(pid, :buffer, buffers, for_pad: other_ref)
      state
    else
      %{direction: :input} ->
        raise PadDirectionError, action: :buffer, direction: :input, pad: pad_ref

      %{end_of_stream?: true} ->
        raise ElementError,
              "Tried to send a buffer through a pad #{inspect(pad_ref)} where end of stream has already been sent"

      %{caps: nil} ->
        raise ElementError,
              "Tried to send a buffer through a pad #{inspect(pad_ref)} where caps have not been sent yet"
    end
  end

  defp send_buffer(_pad_ref, invalid_value, _state) do
    raise ElementError, "Tried to send an invalid buffer #{inspect(invalid_value)}"
  end

  @spec send_caps(Pad.ref_t(), Caps.t(), State.t()) :: State.t()
  def send_caps(pad_ref, caps, state) do
    Membrane.Logger.debug("""
    Sending caps through pad #{inspect(pad_ref)}
    Caps: #{inspect(caps)}
    """)

    pad_data = PadModel.get_data!(state, pad_ref)

    withl data: %{direction: :output, pid: pid, other_ref: other_ref} <- pad_data,
          caps: true <- Caps.Matcher.match?(pad_data.accepted_caps, caps) do
      state = PadModel.set_data!(state, pad_ref, :caps, caps)
      Message.send(pid, :caps, caps, for_pad: other_ref)
      state
    else
      data: %{direction: :input} ->
        raise PadDirectionError, action: :caps, direction: :input, pad: pad_ref

      caps: false ->
        raise ElementError, """
        Trying to send caps that do not match the specification
        Caps being sent: #{inspect(caps, pretty: true)}
        Allowed caps spec: #{inspect(pad_data.accepted_caps, pretty: true)}\
        """
    end
  end

  @spec supply_demand(
          Pad.ref_t(),
          Action.demand_size_t(),
          State.t()
        ) :: State.t()
  defp supply_demand(pad_ref, 0, state) do
    Membrane.Logger.debug_verbose("Ignoring demand of size of 0 on pad #{inspect(pad_ref)}")
    state
  end

  defp supply_demand(pad_ref, size, _state)
       when is_integer(size) and size < 0 do
    raise ElementError,
          "Tried to request a negative demand of size #{inspect(size)} on pad #{inspect(pad_ref)}"
  end

  defp supply_demand(pad_ref, size, state) do
    with %{direction: :input, mode: :pull, demand_mode: :manual} <-
           PadModel.get_data!(state, pad_ref) do
      DemandHandler.supply_demand(pad_ref, size, state)
    else
      %{direction: :output} ->
        raise PadDirectionError, action: :demand, direction: :output, pad: pad_ref

      %{mode: :push} ->
        raise ElementError,
              "Tried to request a demand on pad #{inspect(pad_ref)} working in push mode"

      %{demand_mode: :auto} ->
        raise ElementError,
              "Tried to request a demand on pad #{inspect(pad_ref)} that has demand mode set to auto"
    end
  end

  @spec handle_redemand(Pad.ref_t(), State.t()) :: State.t()
  defp handle_redemand(pad_ref, %{type: type} = state)
       when type in [:source, :filter, :endpoint] do
    with %{direction: :output, mode: :pull, demand_mode: :manual} <-
           PadModel.get_data!(state, pad_ref) do
      DemandHandler.handle_redemand(pad_ref, state)
    else
      %{direction: :input} ->
        raise ElementError, "Tried to make a redemand on input pad #{inspect(pad_ref)}"

      %{mode: :push} ->
        raise ElementError,
              "Tried to make a redemand on pad #{inspect(pad_ref)} working in push mode"

      %{demand_mode: :auto} ->
        raise ElementError,
              "Tried to make a redemand on pad #{inspect(pad_ref)} that has demand mode set to auto"
    end
  end

  @spec send_event(Pad.ref_t(), Event.t(), State.t()) :: State.t()
  defp send_event(pad_ref, event, state) do
    Membrane.Logger.debug_verbose("""
    Sending event through pad #{inspect(pad_ref)}
    Event: #{inspect(event)}
    """)

    if Event.event?(event) do
      %{pid: pid, other_ref: other_ref} = PadModel.get_data!(state, pad_ref)
      state = handle_event(pad_ref, event, state)
      Message.send(pid, :event, event, for_pad: other_ref)
      state
    else
      raise Membrane.ElementError,
            "Tried to send invalid event #{inspect(event)} on pad #{inspect(pad_ref)}"
    end
  end

  @spec handle_event(Pad.ref_t(), Event.t(), State.t()) :: State.t()
  defp handle_event(pad_ref, %Events.EndOfStream{}, state) do
    with %{direction: :output, end_of_stream?: false} <- PadModel.get_data!(state, pad_ref) do
      state = PadController.remove_pad_associations(pad_ref, state)
      PadModel.set_data!(state, pad_ref, :end_of_stream?, true)
    else
      %{direction: :input} ->
        raise PadDirectionError, action: "end of stream", direction: :input, pad: pad_ref

      %{end_of_stream?: true} ->
        raise ElementError, "End of stream already set on pad #{inspect(pad_ref)}"
    end
  end

  defp handle_event(_pad_ref, _event, state), do: state
end
