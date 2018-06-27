defmodule Membrane.Core.Element.ActionHandler do
  @moduledoc false
  # Module containing action handlers common for elements of all types.

  alias Membrane.{Buffer, Caps, Core, Element, Event, Message, Pad}
  alias Core.Element.{Common, State}
  import Element.Pad, only: [is_pad_name: 1]
  use Core.Element.Log
  use Membrane.Helper
  use Membrane.Mixins.CallbackHandler

  @impl CallbackHandler
  def handle_action({:event, {pad_name, event}}, _cb, _params, state)
      when is_pad_name(pad_name) do
    send_event(pad_name, event, state)
  end

  def handle_action({:message, message}, _cb, _params, state),
    do: send_message(message, state)

  def handle_action({:split, {callback, args_list}}, cb, params, state) do
    CallbackHandler.exec_and_handle_splitted_callback(
      callback,
      cb,
      __MODULE__,
      params,
      args_list,
      state
    )
  end

  def handle_action({:playback_change, :suspend}, cb, _params, state)
      when cb in [:handle_prepare, :handle_play, :handle_stop] do
    state |> Element.suspend_playback_change()
  end

  def handle_action({:playback_change, :resume}, _cb, _params, state),
    do: state |> Element.continue_playback_change()

  def handle_action({:buffer, {pad_name, buffers}}, cb, _params, %State{type: type} = state)
      when type in [:source, :filter] and is_pad_name(pad_name) do
    send_buffer(pad_name, buffers, cb, state)
  end

  def handle_action({:caps, {pad_name, caps}}, _cb, _params, %State{type: type} = state)
      when type in [:source, :filter] and is_pad_name(pad_name) do
    send_caps(pad_name, caps, state)
  end

  def handle_action({:redemand, src_name}, cb, _params, %State{type: type} = state)
      when type in [:source, :filter] and is_pad_name(src_name) and
             cb not in [:handle_demand, :handle_process] do
    handle_redemand(src_name, state)
  end

  def handle_action({:forward, data}, cb, params, %State{type: :filter} = state)
      when cb in [:handle_caps, :handle_event, :handle_process] do
    {action, dir} =
      case {cb, params} do
        {:handle_process, _} -> {:buffer, :source}
        {:handle_caps, _} -> {:caps, :source}
        {:handle_event, %{direction: :sink}} -> {:event, :source}
        {:handle_event, %{direction: :source}} -> {:event, :sink}
      end

    pads = state |> State.get_pads_data(dir) |> Map.keys()

    pads
    |> Helper.Enum.reduce_with(state, fn pad, st ->
      handle_action({action, {pad, data}}, cb, params, st)
    end)
  end

  def handle_action({:demand, pad_name}, :handle_demand, params, %State{type: :filter} = state)
      when is_pad_name(pad_name) do
    handle_action({:demand, {pad_name, 1}}, :handle_demand, params, state)
  end

  def handle_action(
        {:demand, {pad_name, size}},
        :handle_demand,
        %{source: src_name} = params,
        %State{type: :filter} = state
      )
      when is_pad_name(pad_name) and is_integer(size) do
    handle_action({:demand, {pad_name, {:source, src_name}, size}}, :handle_demand, params, state)
  end

  def handle_action(
        {:demand, {pad_name, {:source, src_name}, size}},
        cb,
        _params,
        %State{type: :filter} = state
      )
      when is_pad_name(pad_name) and is_pad_name(src_name) and is_integer(size) do
    handle_demand(pad_name, {:source, src_name}, :normal, size, cb, state)
  end

  def handle_action(
        {:demand, {pad_name, :self, size}},
        cb,
        _params,
        %State{type: :filter} = state
      )
      when is_pad_name(pad_name) and is_integer(size) do
    handle_demand(pad_name, :self, :normal, size, cb, state)
  end

  def handle_action({:demand, pad_name}, cb, params, %State{type: :sink} = state)
      when is_pad_name(pad_name) do
    handle_action({:demand, {pad_name, 1}}, cb, params, state)
  end

  def handle_action({:demand, {pad_name, size}}, cb, _params, %State{type: :sink} = state)
      when is_pad_name(pad_name) and is_integer(size) do
    handle_demand(pad_name, :self, :normal, size, cb, state)
  end

  def handle_action(
        {:demand, {pad_name, {:set_to, size}}},
        cb,
        _params,
        %State{type: :sink} = state
      )
      when is_pad_name(pad_name) and is_integer(size) do
    handle_demand(pad_name, :self, :set, size, cb, state)
  end

  def handle_action(action, callback, _params, state) do
    warn_error(
      """
      Elements' #{inspect(state.module)} #{inspect(callback)} callback returned
      invalid action: #{inspect(action)}. For possible actions are check types
      in Membrane.Element.Action module. Keep in mind that some actions are
      available in different formats or unavailable for some callbacks,
      element types, playback states or under some other conditions.
      """,
      {:invalid_action, action: action, callback: callback, module: state |> Map.get(:module)},
      state
    )
  end

  @impl CallbackHandler
  def handle_actions(actions, callback, handler_params, state),
    do:
      super(
        actions |> join_buffers(),
        callback,
        handler_params,
        state
      )

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

  @spec send_buffer(Pad.name_t(), atom, [Buffer.t()], State.t()) :: :ok | {:error, any}
  def send_buffer(
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

  def send_buffer(pad_name, %Buffer{} = buffer, callback, state) do
    send_buffer(pad_name, [buffer], callback, state)
  end

  def send_buffer(pad_name, buffers, _callback, state) do
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

    with {:ok, %{mode: mode, pid: pid, other_name: other_name, options: options, eos: false}} <-
           state |> State.get_pad_data(:source, pad_name) do
      {:ok, state} =
        case mode do
          :pull ->
            buf_size = Buffer.Metric.from_unit(options.other_demand_in).buffers_size(buffers)
            state |> State.update_pad_data(:source, pad_name, :demand, &{:ok, &1 - buf_size})

          :push ->
            {:ok, state}
        end

      send(pid, {:membrane_buffer, [buffers, other_name]})
      {:ok, state}
    else
      {:ok, %{eos: true}} ->
        warn_error(
          [
            """
            Error while sending buffers to pad: #{inspect(pad_name)}
            Buffers:
            """,
            Buffer.print(buffers)
          ],
          :eos_already_sent,
          state
        )

      {:error, :unknown_pad} ->
        handle_unknown_pad(pad_name, :source, :buffer, state)

      {:error, reason} ->
        warn_error(
          [
            """
            Error while sending buffers to pad: #{inspect(pad_name)}
            Buffers:
            """,
            Buffer.print(buffers)
          ],
          reason,
          state
        )
    end
  end

  @spec send_caps(Pad.name_t(), Caps.t(), State.t()) :: :ok
  def send_caps(pad_name, caps, state) do
    debug(
      """
      Sending caps through pad #{inspect(pad_name)}
      Caps: #{inspect(caps)}
      """,
      state
    )

    with {:ok, %{accepted_caps: accepted_caps, pid: pid, other_name: other_name}} <-
           state |> State.get_pad_data(:source, pad_name),
         {true, _} <- {Caps.Matcher.match?(accepted_caps, caps), accepted_caps} do
      send(pid, {:membrane_caps, [caps, other_name]})
      state |> State.set_pad_data(:source, pad_name, :caps, caps)
    else
      {false, accepted_caps} ->
        warn_error(
          """
          Trying to send caps that are not specified in known_source_pads
          Caps being sent: #{inspect(caps)}
          Allowed caps spec: #{inspect(accepted_caps)}
          """,
          :invalid_caps,
          state
        )

      {:error, :unknown_pad} ->
        handle_unknown_pad(pad_name, :source, :event, state)

      {:error, reason} ->
        warn_error(
          """
          Error while sending caps to pad: #{inspect(pad_name)}
          Caps: #{inspect(caps)}
          """,
          reason,
          state
        )
    end
  end

  @spec handle_demand(
          Pad.name_t(),
          {:source, Pad.name_t()} | :self,
          :normal | :set,
          pos_integer,
          atom,
          State.t()
        ) :: :ok | {:error, any}
  def handle_demand(pad_name, source, type, size, callback, state)

  def handle_demand(
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

  def handle_demand(pad_name, _source, _type, 0, callback, state) do
    debug(
      """
      Ignoring demand of size of 0 requested by callback #{inspect(callback)}
      on pad #{inspect(pad_name)}.
      """,
      state
    )

    {:ok, state}
  end

  def handle_demand(pad_name, _source, _type, size, callback, state)
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

  def handle_demand(pad_name, source, type, size, callback, state) do
    debug("Requesting demand of size #{inspect(size)} on pad #{inspect(pad_name)}", state)

    with {:sink, {:ok, %{mode: :pull}}} <- {:sink, state |> State.get_pad_data(:sink, pad_name)},
         {:source, {:ok, %{mode: :pull}}} <-
           {:source,
            case source do
              {:source, src_name} -> state |> State.get_pad_data(:source, src_name)
              :self -> {:ok, %{mode: :pull}}
            end} do
      case callback do
        cb when cb in [:handle_write, :handle_process] ->
          send(self(), {:membrane_self_demand, [pad_name, source, type, size]})
          {:ok, state}

        _ ->
          Common.handle_self_demand(pad_name, source, type, size, state)
      end
    else
      {_direction, {:ok, %{mode: :push}}} ->
        handle_invalid_pad_mode(pad_name, :pull, :demand, state)

      {direction, {:error, :unknown_pad}} ->
        handle_unknown_pad(pad_name, direction, :demand, state)
    end
  end

  @spec handle_redemand(Pad.name_t(), State.t()) :: {:ok, State.t()} | no_return()
  def handle_redemand(src_name, state) do
    with {:ok, %{mode: :pull}} <- state |> State.get_pad_data(:source, src_name) do
      Common.handle_redemand(src_name, state)
    else
      {:ok, %{mode: :push}} ->
        handle_invalid_pad_mode(src_name, :pull, :demand, state)

      {:error, :unknown_pad} ->
        handle_unknown_pad(src_name, :source, :demand, state)
    end
  end

  @spec send_event(Pad.name_t(), Event.t(), State.t()) :: :ok
  def send_event(pad_name, event, state) do
    debug(
      """
      Sending event through pad #{inspect(pad_name)}
      Event: #{inspect(event)}
      """,
      state
    )

    with {:ok, %{pid: pid, other_name: other_name}} <- State.get_pad_data(state, :any, pad_name),
         {:ok, state} <- handle_event(pad_name, event, state) do
      send(pid, {:membrane_event, [event, other_name]})
      {:ok, state}
    else
      {:error, :unknown_pad} ->
        handle_unknown_pad(pad_name, :any, :event, state)

      {:error, reason} ->
        warn_error(
          """
          Error while sending event to pad: #{inspect(pad_name)}
          Event: #{inspect(event)}
          """,
          reason,
          state
        )
    end
  end

  defp handle_event(pad_name, %Event{type: :eos}, state) do
    with %{direction: :source, eos: false} <- state |> State.get_pad_data!(:any, pad_name) do
      state |> State.set_pad_data(:source, pad_name, :eos, true)
    else
      %{direction: :sink} -> {:error, {:cannot_send_eos_through_sink, pad_name}}
      %{eos: true} -> {:error, {:eos_already_sent, pad_name}}
    end
  end

  defp handle_event(_pad_name, _event, state), do: {:ok, state}

  @spec send_message(Message.t(), State.t()) :: :ok
  def send_message(%Message{} = message, %State{message_bus: nil} = state) do
    debug("Dropping #{inspect(message)} as message bus is undefined", state)
    {:ok, state}
  end

  def send_message(%Message{} = message, %State{message_bus: message_bus, name: name} = state) do
    debug("Sending message #{inspect(message)} (message bus: #{inspect(message_bus)})", state)
    send(message_bus, [:membrane_message, name, message])
    {:ok, state}
  end

  defp handle_invalid_pad_mode(pad_name, expected_mode, action_name, state) do
    mode =
      case expected_mode do
        :pull -> :push
        :push -> :pull
      end

    warn_error(
      """
      Pad "#{inspect(pad_name)}" is working in invalid mode: #{inspect(mode)}.

      This is probably a bug in element. It requested an action
      "#{inspect(action_name)}" on pad "#{inspect(pad_name)}", but the pad is not
      working in #{inspect(expected_mode)} mode as it is supposed to.
      """,
      {:invalid_pad_mode, pad_name, mode},
      state
    )
  end

  defp handle_unknown_pad(pad_name, expected_direction, action_name, state) do
    warn_error(
      """
      Pad "#{inspect(pad_name)}" has not been found.

      This is probably a bug in element. It requested an action
      "#{inspect(action_name)}" on pad "#{inspect(pad_name)}", but such pad has not
      been found. #{
        if expected_direction != :any do
          "It either means that it does not exist, or it is not a" <>
            "#{inspect(expected_direction)} pad."
        else
          ""
        end
      }
      """,
      {:unknown_pad, pad_name},
      state
    )
  end
end
