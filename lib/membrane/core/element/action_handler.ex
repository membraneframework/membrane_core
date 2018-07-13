defmodule Membrane.Core.Element.ActionHandler do
  @moduledoc false
  # Module validating and executing actions returned by element's callbacks.

  alias Membrane.{Buffer, Caps, Core, Element, Event, Message, Pad}
  alias Core.Element.{DemandController, LifecycleController, DemandHandler, PadModel, State}
  alias Core.PlaybackHandler
  alias Element.{Action, Pad}
  require PadModel
  import Element.Pad, only: [is_pad_name: 1]
  use Core.Element.Log
  use Membrane.Helper
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
           action: action, callback: callback, module: state |> Map.get(:module), reason: reason},
          state
        )
    end
  end

  @spec do_handle_action(Action.t(), callback :: atom, params :: map, State.t()) ::
          State.stateful_try_t()
  defp do_handle_action({:event, {pad_name, event}}, _cb, _params, state)
       when is_pad_name(pad_name) do
    send_event(pad_name, event, state)
  end

  defp do_handle_action({:message, message}, _cb, _params, state),
    do: send_message(message, state)

  defp do_handle_action({:split, {callback, args_list}}, cb, params, state) do
    CallbackHandler.exec_and_handle_splitted_callback(
      callback,
      cb,
      __MODULE__,
      params,
      args_list,
      state
    )
  end

  defp do_handle_action({:playback_change, :suspend}, cb, _params, state)
       when cb in [:handle_prepare, :handle_play, :handle_stop] do
    PlaybackHandler.suspend_playback_change(state)
  end

  defp do_handle_action({:playback_change, :resume}, _cb, _params, state),
    do: PlaybackHandler.continue_playback_change(LifecycleController, state)

  defp do_handle_action({:buffer, {pad_name, buffers}}, cb, _params, %State{type: type} = state)
       when type in [:source, :filter] and is_pad_name(pad_name) do
    send_buffer(pad_name, buffers, cb, state)
  end

  defp do_handle_action({:caps, {pad_name, caps}}, _cb, _params, %State{type: type} = state)
       when type in [:source, :filter] and is_pad_name(pad_name) do
    send_caps(pad_name, caps, state)
  end

  defp do_handle_action({:redemand, src_name}, cb, _params, %State{type: type} = state)
       when type in [:source, :filter] and is_pad_name(src_name) and
              cb not in [:handle_demand, :handle_process] do
    handle_redemand(src_name, state)
  end

  defp do_handle_action({:forward, data}, cb, params, %State{type: :filter} = state)
       when cb in [:handle_caps, :handle_event, :handle_process] do
    {action, dir} =
      case {cb, params} do
        {:handle_process, _} -> {:buffer, :source}
        {:handle_caps, _} -> {:caps, :source}
        {:handle_event, %{direction: :sink}} -> {:event, :source}
        {:handle_event, %{direction: :source}} -> {:event, :sink}
      end

    pads = PadModel.filter_data(%{direction: dir}, state) |> Map.keys()

    pads
    |> Helper.Enum.reduce_with(state, fn pad, st ->
      handle_action({action, {pad, data}}, cb, params, st)
    end)
  end

  defp do_handle_action(
         {:demand, pad_name},
         :handle_demand,
         params,
         %State{type: :filter} = state
       )
       when is_pad_name(pad_name) do
    handle_action({:demand, {pad_name, 1}}, :handle_demand, params, state)
  end

  defp do_handle_action(
         {:demand, {pad_name, size}},
         :handle_demand,
         %{source: src_name} = params,
         %State{type: :filter} = state
       )
       when is_pad_name(pad_name) and is_integer(size) do
    handle_action({:demand, {pad_name, {:source, src_name}, size}}, :handle_demand, params, state)
  end

  defp do_handle_action(
         {:demand, {pad_name, {:source, src_name}, size}},
         cb,
         _params,
         %State{type: :filter} = state
       )
       when is_pad_name(pad_name) and is_pad_name(src_name) and is_integer(size) do
    handle_demand(pad_name, {:source, src_name}, :set, size, cb, state)
  end

  defp do_handle_action(
         {:demand, {pad_name, :self, size}},
         cb,
         _params,
         %State{type: :filter} = state
       )
       when is_pad_name(pad_name) and is_integer(size) do
    handle_demand(pad_name, :self, :set, size, cb, state)
  end

  defp do_handle_action({:demand, pad_name}, cb, params, %State{type: :sink} = state)
       when is_pad_name(pad_name) do
    handle_action({:demand, {pad_name, 1}}, cb, params, state)
  end

  defp do_handle_action({:demand, {pad_name, size}}, cb, _params, %State{type: :sink} = state)
       when is_pad_name(pad_name) and is_integer(size) do
    handle_demand(pad_name, :self, :increase, size, cb, state)
  end

  defp do_handle_action(
         {:demand, {pad_name, {:set_to, size}}},
         cb,
         _params,
         %State{type: :sink} = state
       )
       when is_pad_name(pad_name) and is_integer(size) do
    handle_demand(pad_name, :self, :set, size, cb, state)
  end

  defp do_handle_action(_action, _callback, _params, state) do
    {{:error, :invalid_action}, state}
  end

  @impl CallbackHandler
  def handle_actions(actions, callback, handler_params, state) do
    super(
      actions |> join_buffers(),
      callback,
      handler_params,
      state
    )
  end

  defp join_buffers(actions) do
    actions
    |> Helper.Enum.chunk_by(
      fn
        {:buffer, {pad, _}}, {:buffer, {pad2, _}} when pad == pad2 -> true
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

  @spec send_buffer(Pad.name_t(), [Buffer.t()] | Buffer.t(), callback :: atom, State.t()) ::
          State.stateful_try_t()
  defp send_buffer(
         _pad_name,
         _buffer,
         callback,
         %State{playback: %{state: playback_state}} = state
       )
       when playback_state != :playing and callback != :handle_play do
    warn_error(
      "Buffers can only be sent when playing or from handle_play callback",
      {:cannot_send_buffer, playback_state: playback_state, callback: callback},
      state
    )
  end

  defp send_buffer(pad_name, %Buffer{} = buffer, callback, state) do
    send_buffer(pad_name, [buffer], callback, state)
  end

  defp send_buffer(pad_name, buffers, _callback, state) do
    debug(
      [
        """
        Sending buffers through pad #{inspect(pad_name)},
        Buffers:
        """,
        Buffer.print(buffers)
      ],
      state
    )

    with :ok <- PadModel.assert_data(pad_name, %{direction: :source, eos: false}, state) do
      %{mode: mode, pid: pid, other_name: other_name, options: options} =
        PadModel.get_data!(pad_name, state)

      state = handle_buffer(pad_name, mode, options, buffers, state)
      send(pid, {:membrane_buffer, [buffers, other_name]})
      {:ok, state}
    else
      {:error, reason} -> handle_pad_error(reason, state)
    end
  end

  @spec handle_buffer(Pad.name_t(), Pad.mode_t(), map, [Buffer.t()] | Buffer.t(), State.t()) ::
          State.t()
  defp handle_buffer(pad_name, :pull, options, buffers, state) do
    buf_size = Buffer.Metric.from_unit(options.other_demand_in).buffers_size(buffers)

    PadModel.update_data!(
      pad_name,
      :demand,
      &(&1 - buf_size),
      state
    )
  end

  defp handle_buffer(_pad_name, :push, _options, _buffers, state) do
    state
  end

  @spec send_caps(Pad.name_t(), Caps.t(), State.t()) :: State.stateful_try_t()
  def send_caps(pad_name, caps, state) do
    debug(
      """
      Sending caps through pad #{inspect(pad_name)}
      Caps: #{inspect(caps)}
      """,
      state
    )

    withl pad: :ok <- PadModel.assert_data(pad_name, %{direction: :source}, state),
          do: accepted_caps = PadModel.get_data!(pad_name, :accepted_caps, state),
          caps: true <- Caps.Matcher.match?(accepted_caps, caps) do
      {%{pid: pid, other_name: other_name}, state} =
        PadModel.get_and_update_data!(
          pad_name,
          fn data -> %{data | caps: caps} ~> {&1, &1} end,
          state
        )

      send(pid, {:membrane_caps, [caps, other_name]})
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

  @spec handle_demand(
          Pad.name_t(),
          {:source, Pad.name_t()} | :self,
          type :: :increase | :set,
          size :: pos_integer,
          callback :: atom,
          State.t()
        ) :: State.stateful_try_t()
  defp handle_demand(pad_name, source, type, size, callback, state)

  defp handle_demand(
         _pad_name,
         _source,
         _type,
         _size,
         callback,
         %State{playback: %{state: playback_state}} = state
       )
       when playback_state != :playing and callback != :handle_play do
    warn_error(
      "Demand can only be requested when playing or from handle_play callback",
      {:cannot_handle_demand, playback_state: playback_state, callback: callback},
      state
    )
  end

  defp handle_demand(pad_name, _source, _type, 0, callback, state) do
    debug(
      """
      Ignoring demand of size of 0 requested by callback #{inspect(callback)}
      on pad #{inspect(pad_name)}.
      """,
      state
    )

    {:ok, state}
  end

  defp handle_demand(pad_name, _source, _type, size, callback, state)
       when size < 0 do
    warn_error(
      """
      Callback #{inspect(callback)} requested demand of invalid size of #{size}
      on pad #{inspect(pad_name)}. Demands' sizes should be positive (0-sized
      demands are ignored).
      """,
      :negative_demand,
      state
    )
  end

  defp handle_demand(pad_name, source, type, size, callback, state) do
    debug("Requesting demand of size #{inspect(size)} on pad #{inspect(pad_name)}", state)

    sink_assertion = PadModel.assert_data(pad_name, %{direction: :sink, mode: :pull}, state)

    source_assertion =
      case source do
        {:source, src_name} -> PadModel.assert_data(src_name, %{direction: :source}, state)
        :self -> :ok
      end

    with :ok <- sink_assertion,
         :ok <- source_assertion do
      if callback in [:handle_write, :handle_process] do
        send(self(), {:membrane_demand, [pad_name, source, type, size]})
        {:ok, state}
      else
        DemandHandler.handle_demand(pad_name, source, type, size, state)
      end
    else
      {:error, reason} -> handle_pad_error(reason, state)
    end
  end

  @spec handle_redemand(Pad.name_t(), State.t()) :: State.stateful_try_t()
  defp handle_redemand(src_name, state) do
    with :ok <- PadModel.assert_data(src_name, %{direction: :source, mode: :pull}, state) do
      DemandController.handle_demand(src_name, 0, state)
    else
      {:error, reason} -> handle_pad_error(reason, state)
    end
  end

  @spec send_event(Pad.name_t(), Event.t(), State.t()) :: State.stateful_try_t()
  defp send_event(pad_name, event, state) do
    debug(
      """
      Sending event through pad #{inspect(pad_name)}
      Event: #{inspect(event)}
      """,
      state
    )

    withl pad: {:ok, %{pid: pid, other_name: other_name}} <- PadModel.get_data(pad_name, state),
          handler: {:ok, state} <- handle_event(pad_name, event, state) do
      send(pid, {:membrane_event, [event, other_name]})
      {:ok, state}
    else
      pad: {:error, reason} -> handle_pad_error(reason, state)
      handler: {{:error, reason}, state} -> {{:error, reason}, state}
    end
  end

  @spec handle_event(Pad.name_t(), Event.t(), State.t()) :: State.stateful_try_t()
  defp handle_event(pad_name, %Event{type: :eos}, state) do
    with %{direction: :source, eos: false} <- PadModel.get_data!(pad_name, state) do
      {:ok, PadModel.set_data!(pad_name, :eos, true, state)}
    else
      %{direction: :sink} -> {{:error, {:cannot_send_eos_through_sink, pad_name}}, state}
      %{eos: true} -> {{:error, {:eos_already_sent, pad_name}}, state}
    end
  end

  defp handle_event(_pad_name, _event, state), do: {:ok, state}

  @spec send_message(Message.t(), State.t()) :: {:ok, State.t()}
  defp send_message(%Message{} = message, %State{message_bus: nil} = state) do
    debug("Dropping #{inspect(message)} as message bus is undefined", state)
    {:ok, state}
  end

  defp send_message(%Message{} = message, %State{message_bus: message_bus, name: name} = state) do
    debug("Sending message #{inspect(message)} (message bus: #{inspect(message_bus)})", state)
    send(message_bus, [:membrane_message, name, message])
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
         {:invalid_pad_data, name: name, pattern: pattern, data: data} = reason,
         state
       ) do
    warn_error(
      """
      Properties of pad #{inspect(name)} do not match the pattern:
      #{inspect(pattern)}
      Pad properties: #{inspect(data)}
      """,
      reason,
      state
    )
  end
end
