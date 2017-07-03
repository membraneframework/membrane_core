defmodule Membrane.Element.Common do

  use Membrane.Mixins.Log
  alias Membrane.Element.State
  alias Membrane.Helper
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
          |> Common.orWarnError("Error while handling message")
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
    with \
      :ok <- (if accepted_caps == :any || caps in accepted_caps do :ok else :invalid_caps end),
      {:ok, state} <- exec_and_handle_callback(:handle_event, [pad_name, caps], state)
    do {:ok, state}
    else
      :invalid_caps ->
        warnError """
        Received caps: #{inspect caps} that are not specified in known_sink_pads
        for pad #{inspect pad_name}. Acceptable caps are:
        #{accepted_caps |> Enum.map(&inspect/1) |> Enum.join(", ")}
        """, :invalid_caps
      {:error, reason} -> warnError "Error while handling caps", reason
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
    exec_and_handle_callback(:handle_event, [pad_name, event], state)
      |> orWarnError("Error while handling event")
  end

  def exec_and_handle_callback(cb, actions_cb \\ nil, args, %State{module: module, internal_state: internal_state} = state) do
    actions_cb = actions_cb || cb
    with \
      {:call, {:ok, {actions, new_internal_state}}} <- {:call, apply(module, cb, args ++ [internal_state]) |> handle_callback_result(cb)},
      {:handle, {:ok, state}} <- {:handle, actions |> module.base_module.handle_actions(actions_cb, %State{state | internal_state: new_internal_state})}
    do {:ok, state}
    else
      {:call, {:error, reason}} -> warnError "Error while executing callback #{inspect cb}", reason
      {:handle, {:error, reason}} -> warnError "Error while handling actions returned by callback #{inspect cb}", reason
    end
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
