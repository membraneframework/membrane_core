defmodule Membrane.Core.Element.ActionHandler do
  @moduledoc false
  # Module validating and executing actions returned by element's callbacks.

  alias Membrane.{Buffer, Caps, Core, Element, Event, Notification}
  alias Core.Element.{DemandHandler, LifecycleController, PadModel, State}
  alias Core.{Message, PlaybackHandler}
  alias Element.{Action, Pad}
  require Message
  require PadModel
  import Element.Pad, only: [is_pad_ref: 1]
  use Core.Element.Log
  use Bunch
  use Membrane.Core.CallbackHandler

  @impl CallbackHandler
  def handle_action(action, callback, params, state) do
    with {:ok, state} <- do_handle_action(action, callback, params, state) do
      {:ok, state}
    else
      {{:error, :invalid_action}, state} ->
        warn_error(
          """
          Elements' #{inspect(state.module)} #{inspect(callback)} callback returned
          invalid action: #{inspect(action)}. For possible actions are check types
          in Membrane.Element.Action module. Keep in mind that some actions are
          available in different formats or unavailable for some callbacks,
          element types, playback states or under some other conditions.
          """,
          {:invalid_action,
           action: action, callback: callback, module: state |> Map.get(:module)},
          state
        )

      {{:error, reason}, state} ->
        warn_error(
          """
          Encountered an error while processing action #{inspect(action)}.
          This is probably a bug in element, which passed invalid arguments to the
          action, such as a pad with invalid direction. For more details, see the
          reason section.
          """,
          {:cannot_handle_action,
           reason: reason, action: action, callback: callback, module: state |> Map.get(:module)},
          state
        )
    end
  end

  defguardp is_demand_size(size) when is_integer(size) or is_function(size)

  @spec do_handle_action(Action.t(), callback :: atom, params :: map, State.t()) ::
          State.stateful_try_t()
  defp do_handle_action({action, _}, _cb, _params, %State{playback: %{state: :stopped}} = state)
       when action in [:buffer, :event, :caps, :demand, :redemand, :forward] do
    {{:error, :element_stopped}, state}
  end

  defp do_handle_action({:event, {pad_ref, event}}, _cb, _params, state)
       when is_pad_ref(pad_ref) do
    send_event(pad_ref, event, state)
  end

  defp do_handle_action({:notify, notification}, _cb, _params, state),
    do: send_notification(notification, state)

  defp do_handle_action({:split, {callback, args_list}}, cb, params, state) do
    CallbackHandler.exec_and_handle_splitted_callback(
      callback,
      cb,
      __MODULE__,
      params |> Map.merge(%{skip_invoking_redemands: true}),
      args_list,
      state
    )
  end

  defp do_handle_action({:playback_change, :suspend}, cb, _params, state)
       when cb in [
              :handle_stopped_to_prepared,
              :handle_playing_to_prepared,
              :handle_prepared_to_playing,
              :handle_prepared_to_stopped
            ] do
    PlaybackHandler.suspend_playback_change(state)
  end

  defp do_handle_action({:playback_change, :resume}, _cb, _params, state),
    do: PlaybackHandler.continue_playback_change(LifecycleController, state)

  defp do_handle_action({:buffer, {pad_ref, buffers}}, cb, _params, %State{type: type} = state)
       when type in [:source, :filter] and is_pad_ref(pad_ref) do
    send_buffer(pad_ref, buffers, cb, state)
  end

  defp do_handle_action({:caps, {pad_ref, caps}}, _cb, _params, %State{type: type} = state)
       when type in [:source, :filter] and is_pad_ref(pad_ref) do
    send_caps(pad_ref, caps, state)
  end

  defp do_handle_action({:redemand, out_refs}, cb, params, state)
       when is_list(out_refs) do
    out_refs
    |> Bunch.Enum.try_reduce(state, fn out_ref, state ->
      do_handle_action({:redemand, out_ref}, cb, params, state)
    end)
  end

  defp do_handle_action({:redemand, out_ref}, cb, _params, %State{type: type} = state)
       when type in [:source, :filter] and is_pad_ref(out_ref) and
              {type, cb} != {:filter, :handle_demand} do
    handle_redemand(out_ref, state)
  end

  defp do_handle_action({:forward, data}, cb, params, %State{type: :filter} = state)
       when cb in [:handle_caps, :handle_event, :handle_process_list] do
    {action, dir} =
      case {cb, params} do
        {:handle_process_list, _} -> {:buffer, :output}
        {:handle_caps, _} -> {:caps, :output}
        {:handle_event, %{direction: :input}} -> {:event, :output}
        {:handle_event, %{direction: :output}} -> {:event, :input}
      end

    pads = state |> PadModel.filter_data(%{direction: dir}) |> Map.keys()

    pads
    |> Bunch.Enum.try_reduce(state, fn pad, st ->
      do_handle_action({action, {pad, data}}, cb, params, st)
    end)
  end

  defp do_handle_action(
         {:demand, pad_ref},
         cb,
         params,
         %State{type: type} = state
       )
       when is_pad_ref(pad_ref) and type in [:sink, :filter] do
    do_handle_action({:demand, {pad_ref, 1}}, cb, params, state)
  end

  defp do_handle_action(
         {:demand, {pad_ref, size}},
         cb,
         params,
         %State{type: type} = state
       )
       when is_pad_ref(pad_ref) and is_demand_size(size) and type in [:sink, :filter] do
    supply_demand(pad_ref, size, cb, params[:supplying_demand?] || false, state)
  end

  defp do_handle_action(_action, _callback, _params, state) do
    {{:error, :invalid_action}, state}
  end

  @impl CallbackHandler
  def handle_actions(actions, callback, handler_params, state) do
    actions_after_redemand =
      actions
      |> Enum.drop_while(fn
        {:redemand, _} -> false
        _ -> true
      end)
      |> Enum.drop(1)

    if actions_after_redemand != [] do
      {{:error, :actions_after_redemand}, state}
    else
      super(actions |> join_buffers(), callback, handler_params, state)
    end
  end

  defp join_buffers(actions) do
    actions
    |> Bunch.Enum.chunk_by_prev(
      fn
        {:buffer, {pad, _}}, {:buffer, {pad, _}} -> true
        _, _ -> false
      end,
      fn
        [{:buffer, {pad, _}} | _] = buffers ->
          {:buffer, {pad, buffers |> Enum.map(fn {_, {_, b}} -> [b] end) |> List.flatten()}}

        [other] ->
          other
      end
    )
  end

  @spec send_buffer(Pad.ref_t(), [Buffer.t()] | Buffer.t(), callback :: atom, State.t()) ::
          State.stateful_try_t()
  defp send_buffer(
         _pad_ref,
         _buffer,
         callback,
         %State{playback: %{state: playback_state}} = state
       )
       when playback_state != :playing and callback != :handle_prepared_to_playing do
    warn_error(
      "Buffers can only be sent when playing or from handle_prepared_to_playing callback",
      {:cannot_send_buffer, playback_state: playback_state, callback: callback},
      state
    )
  end

  defp send_buffer(pad_ref, %Buffer{} = buffer, callback, state) do
    send_buffer(pad_ref, [buffer], callback, state)
  end

  defp send_buffer(pad_ref, buffers, _callback, state) do
    debug(
      [
        """
        Sending buffers through pad #{inspect(pad_ref)},
        Buffers:
        """,
        Buffer.print(buffers)
      ],
      state
    )

    with :ok <- PadModel.assert_data(state, pad_ref, %{direction: :output, end_of_stream?: false}) do
      %{mode: mode, pid: pid, other_ref: other_ref, other_demand_unit: other_demand_unit} =
        PadModel.get_data!(state, pad_ref)

      state = handle_buffer(pad_ref, mode, other_demand_unit, buffers, state)
      Message.send(pid, :buffer, [buffers, other_ref])
      {:ok, state}
    else
      {:error, reason} -> handle_pad_error(reason, state)
    end
  end

  @spec handle_buffer(
          Pad.ref_t(),
          Pad.mode_t(),
          Buffer.Metric.unit_t(),
          [Buffer.t()] | Buffer.t(),
          State.t()
        ) :: State.t()
  defp handle_buffer(pad_ref, :pull, other_demand_unit, buffers, state) do
    buf_size = Buffer.Metric.from_unit(other_demand_unit).buffers_size(buffers)

    state |> PadModel.update_data!(pad_ref, :demand, &(&1 - buf_size))
  end

  defp handle_buffer(_pad_ref, :push, _options, _buffers, state) do
    state
  end

  @spec send_caps(Pad.ref_t(), Caps.t(), State.t()) :: State.stateful_try_t()
  def send_caps(pad_ref, caps, state) do
    debug(
      """
      Sending caps through pad #{inspect(pad_ref)}
      Caps: #{inspect(caps)}
      """,
      state
    )

    withl pad: :ok <- PadModel.assert_data(state, pad_ref, %{direction: :output}),
          do: accepted_caps = PadModel.get_data!(state, pad_ref, :accepted_caps),
          caps: true <- Caps.Matcher.match?(accepted_caps, caps) do
      {%{pid: pid, other_ref: other_ref}, state} =
        state
        |> PadModel.get_and_update_data!(pad_ref, fn data -> %{data | caps: caps} ~> {&1, &1} end)

      Message.send(pid, :caps, [caps, other_ref])
      {:ok, state}
    else
      caps: false ->
        warn_error(
          """
          Trying to send caps that do not match the specification
          Caps being sent: #{inspect(caps)}
          Allowed caps spec: #{inspect(accepted_caps)}
          """,
          :invalid_caps,
          state
        )

      pad: {:error, reason} ->
        handle_pad_error(reason, state)
    end
  end

  @spec supply_demand(
          Pad.ref_t(),
          Action.demand_size_t(),
          callback :: atom,
          currently_supplying? :: boolean,
          State.t()
        ) :: State.stateful_try_t()

  defp supply_demand(
         _pad_ref,
         _size,
         callback,
         _currently_supplying?,
         %State{playback: %{state: playback_state}} = state
       )
       when playback_state != :playing and callback != :handle_prepared_to_playing do
    warn_error(
      "Demand can only be requested when playing or from handle_prepared_to_playing callback",
      {:cannot_supply_demand, playback_state: playback_state, callback: callback},
      state
    )
  end

  defp supply_demand(pad_ref, 0, callback, _currently_supplying?, state) do
    debug(
      """
      Ignoring demand of size of 0 requested by callback #{inspect(callback)}
      on pad #{inspect(pad_ref)}.
      """,
      state
    )

    {:ok, state}
  end

  defp supply_demand(pad_ref, size, callback, _currently_supplying?, state)
       when is_integer(size) and size < 0 do
    warn_error(
      """
      Callback #{inspect(callback)} requested demand of invalid size of #{size}
      on pad #{inspect(pad_ref)}. Demands' sizes should be positive (0-sized
      demands are ignored).
      """,
      :negative_demand,
      state
    )
  end

  defp supply_demand(pad_ref, size, _callback, currently_supplying?, state) do
    input_assertion = PadModel.assert_data(state, pad_ref, %{direction: :input, mode: :pull})

    with {:ok, state} <- {input_assertion, state},
         {:ok, state} <- DemandHandler.update_demand(pad_ref, size, state) do
      supply_mode = if currently_supplying?, do: :async, else: :sync
      state = DemandHandler.delay_supply(pad_ref, supply_mode, state)

      {:ok, state}
    else
      {{:error, reason}, state} -> handle_pad_error(reason, state)
    end
  end

  @spec handle_redemand(Pad.ref_t(), State.t()) :: State.stateful_try_t()
  defp handle_redemand(out_ref, %{type: type} = state) when type in [:source, :filter] do
    with :ok <- PadModel.assert_data(state, out_ref, %{direction: :output, mode: :pull}) do
      state = DemandHandler.delay_redemand(out_ref, state)
      {:ok, state}
    else
      {:error, reason} -> handle_pad_error(reason, state)
    end
  end

  @spec send_event(Pad.ref_t(), Event.t(), State.t()) :: State.stateful_try_t()
  defp send_event(pad_ref, event, state) do
    debug(
      """
      Sending event through pad #{inspect(pad_ref)}
      Event: #{inspect(event)}
      """,
      state
    )

    withl event: true <- event |> Event.event?(),
          pad: {:ok, %{pid: pid, other_ref: other_ref}} <- PadModel.get_data(state, pad_ref),
          handler: {:ok, state} <- handle_event(pad_ref, event, state) do
      Message.send(pid, :event, [event, other_ref])
      {:ok, state}
    else
      event: false -> {{:error, {:invalid_event, event}}, state}
      pad: {:error, reason} -> handle_pad_error(reason, state)
      handler: {{:error, reason}, state} -> {{:error, reason}, state}
    end
  end

  @spec handle_event(Pad.ref_t(), Event.t(), State.t()) :: State.stateful_try_t()
  defp handle_event(pad_ref, %Event.EndOfStream{}, state) do
    with %{direction: :output, end_of_stream?: false} <- PadModel.get_data!(state, pad_ref) do
      {:ok, PadModel.set_data!(state, pad_ref, :end_of_stream?, true)}
    else
      %{direction: :input} ->
        {{:error, {:cannot_send_end_of_stream_through_input, pad_ref}}, state}

      %{end_of_stream?: true} ->
        {{:error, {:end_of_stream_already_sent, pad_ref}}, state}
    end
  end

  defp handle_event(_pad_ref, _event, state), do: {:ok, state}

  @spec send_notification(Notification.t(), State.t()) :: {:ok, State.t()}
  defp send_notification(notification, %State{watcher: nil} = state) do
    debug("Dropping notification #{inspect(notification)} as watcher is undefined", state)
    {:ok, state}
  end

  defp send_notification(notification, %State{watcher: watcher, name: name} = state) do
    debug("Sending notification #{inspect(notification)} (watcher: #{inspect(watcher)})", state)
    Message.send(watcher, :notification, [name, notification])
    {:ok, state}
  end

  @spec handle_pad_error({reason :: atom, details :: any}, State.t()) ::
          {{:error, reason :: any}, State.t()}
  defp handle_pad_error({:unknown_pad, pad} = reason, state) do
    warn_error(
      """
      Pad "#{inspect(pad)}" has not been found.

      This is probably a bug in element. It requested an action
      on a non-existent pad "#{inspect(pad)}".
      """,
      reason,
      state
    )
  end

  defp handle_pad_error(
         {:invalid_pad_data, ref: ref, pattern: pattern, data: data} = reason,
         state
       ) do
    warn_error(
      """
      Properties of pad #{inspect(ref)} do not match the pattern:
      #{inspect(pattern)}
      Pad properties: #{inspect(data)}
      """,
      reason,
      state
    )
  end
end
