defmodule Membrane.Element.Common do

  use Membrane.Mixins.Log
  alias Membrane.Element.State
  use Membrane.Helper
  alias Membrane.PullBuffer

  defmacro __using__(_) do
    quote do
      def handle_actions(actions, callback, state) do
        actions |> Helper.Enum.reduce_with(state, fn action, state ->
            handle_action action, callback, state
          end)
      end

      def handle_message(message, state) do
        alias Membrane.Element.Common
        Common.exec_and_handle_callback(:handle_other, [message], state)
          |> Common.or_warn_error("Error while handling message")
      end

      def handle_action({:event, {pad_name, event}}, _cb, state), do:
        Membrane.Element.Action.send_event(pad_name, event, state)

      def handle_action({:message, message}, _cb, state), do:
        Membrane.Element.Action.send_message(message, state)

    end
  end

  def handle_caps(:pull, pad_name, caps, state) do
    cond do
      state |> State.get_pad_data!(:sink, pad_name, :buffer) |> PullBuffer.empty?
        -> do_handle_caps pad_name, caps, state
      true -> state |> State.update_pad_data(
        :sink, pad_name, :buffer, & &1 |> PullBuffer.store(:caps, caps))
    end
  end

  def handle_caps(:push, pad_name, caps, state), do:
    do_handle_caps(pad_name, caps, state)

  def do_handle_caps(pad_name, caps, state) do
    accepted_caps = state |> State.get_pad_data!(:sink, pad_name, :accepted_caps)
    params = %{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}
    with \
      :ok <- (if accepted_caps == :any || caps in accepted_caps do :ok else :invalid_caps end),
      {:ok, state} <- exec_and_handle_callback(:handle_caps, [pad_name, caps, params], state)
    do
      state |> State.set_pad_data(:sink, pad_name, :caps, caps)
    else
      :invalid_caps ->
        warn_error """
        Received caps: #{inspect caps} that are not specified in known_sink_pads
        for pad #{inspect pad_name}. Acceptable caps are:
        #{accepted_caps |> Enum.map(&inspect/1) |> Enum.join(", ")}
        """, :invalid_caps
      {:error, reason} -> warn_error "Error while handling caps", reason
    end
  end

  def handle_event(:pull, :sink, pad_name, event, state) do
    cond do
      state |> State.get_pad_data!(:sink, pad_name, :buffer) |> PullBuffer.empty?
        -> do_handle_event pad_name, event, state
      true -> state |> State.update_pad_data(
        :sink, pad_name, :buffer, & &1 |> PullBuffer.store(:event, event))
    end
  end

  def handle_event(_mode, _dir, pad_name, event, state), do:
    do_handle_event(pad_name, event, state)

  def do_handle_event(pad_name, event, state) do
    params = %{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}
    exec_and_handle_callback(:handle_event, [pad_name, event, params], state)
      |> or_warn_error("Error while handling event")
  end

  def handle_link(pad_name, direction, pid, props, state) do
    state |> State.update_pad_data(direction, pad_name, fn data -> data
        |> Map.merge(case direction do
            :sink -> %{buffer: PullBuffer.new(pid, pad_name, props), self_demand: 0}
            :source -> %{demand: 0}
          end)
        |> Map.merge(%{pid: pid})
        ~> (data -> {:ok, data})
      end)
  end

  def handle_pullbuffer_output(pad_name, {:event, e}, state), do:
    do_handle_event(pad_name, e, state)
  def handle_pullbuffer_output(pad_name, {:caps, c}, state), do:
    do_handle_caps(pad_name, c, state)

  def exec_and_handle_callback(cb, actions_cb \\ nil, args, %State{module: module, internal_state: internal_state} = state) do
    actions_cb = actions_cb || cb
    with \
      {:call, {:ok, {actions, new_internal_state}}} <- {:call, apply(module, cb, args ++ [internal_state]) |> handle_callback_result(cb)},
      {:handle, {:ok, state}} <- {:handle, actions
          |> join_buffers
          |> module.base_module.handle_actions(actions_cb, %State{state | internal_state: new_internal_state})
        }
    do {:ok, state}
    else
      {:call, {:error, reason}} -> warn_error "Error while executing callback #{inspect cb}", reason
      {:handle, {:error, reason}} -> warn_error "Error while handling actions returned by callback #{inspect cb}", reason
    end
  end

  defp join_buffers(actions) do
    actions
      |> Helper.Enum.chunk_by(
        fn
          {:buffer, {pad, _}}, {:buffer, {pad2, _}} when pad == pad2 -> true
          _, _ -> false
        end,
        fn
          [{:buffer, {pad, _}}|_] = buffers ->
            {:buffer, {pad, buffers |> Enum.map(fn {_, {_, b}} -> [b] end) |> List.flatten}}
          [other] -> other
        end
      )
  end

  def reduce_something1_results(inputs, state, f) do
    with {:ok, {actions, state}} <- inputs
      |> Membrane.Helper.Enum.map_reduce_with(state,
        fn i, st -> f.(i, st) ~> (
            {:ok, {actions, _state}} = ok when is_list actions -> ok
            {:error, reason} -> {:error, {:internal, reason}}
            other -> {:error, {:other, other}}
        ) end)
    do {:ok, {actions |> List.flatten, state}}
    else
      {:error, {{:internal, reason}, st}} -> {:error, {reason, st}}
      {:error, {{:other, other}, _st}} -> other
    end
  end


  def handle_playback_state(:prepared, :playing, state) do
    with {:ok, state} <- state |> fill_sink_pull_buffers
    do exec_and_handle_callback :handle_play, [], state
    end
  end

  def handle_playback_state(:prepared, :stopped, state), do:
    exec_and_handle_callback :handle_stop, [], state

  def handle_playback_state(ps, :prepared, state) when ps in [:stopped, :playing], do:
    exec_and_handle_callback :handle_prepare, [ps], state


  def fill_sink_pull_buffers(state) do
    state
      |> State.get_pads_data(:sink)
      |> Map.keys
      |> Helper.Enum.reduce_with(state, fn pad_name, st ->
        State.update_pad_data st, :sink, pad_name, :buffer, &PullBuffer.fill/1
      end)
      |> or_warn_error("Unable to fill sink pull buffers")
  end

  def handle_callback_result(result, cb \\ "")
  def handle_callback_result({:ok, {actions, new_internal_state}}, _cb)
  when is_list actions
  do {:ok, {actions, new_internal_state}}
  end
  def handle_callback_result({:error, {reason, new_internal_state}}, cb) do
    warn """
     Elements callback #{inspect cb} returned an error, reason:
     #{inspect reason}

     Elements state: #{inspect new_internal_state}

     Stacktrace:
     #{Exception.format_stacktrace System.stacktrace}
    """
    {:ok, {[], new_internal_state}}
  end
  def handle_callback_result(result, cb) do
    raise """
    Elements' callback replies are expected to be one of:

        {:ok, {actions, state}}
        {:error, {reason, state}}

    where actions is a list that is specific to base type of the element.

    Instead, callback #{inspect cb} returned value of #{inspect result}
    which does not match any of the valid return values.

    This is probably a bug in the element, check if its callbacks return values
    are in the right format.
    """
  end

end
