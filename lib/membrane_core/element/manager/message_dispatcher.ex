defmodule Membrane.Element.Manager.MessageDispatcher do
  alias Membrane.Element.Manager.{State, PlaybackBuffer}
  use Membrane.Helper
  use Membrane.Element.Manager.Log

  def handle_message(message, mode, state) do
    res = do_handle_message(message, mode, state)
    with :ok <- res |> Helper.result_status
    do res
    else
      {:error, reason} ->
        warn_error """
        Pad: cannot handle message: #{inspect message}, mode: #{inspect mode}
        """,
        {:cannot_handle_message, message: message, mode: mode, reason: reason},
        state
    end
  end

  def handle_playback_state(old, new, state) do
    forward :handle_playback_state, [old, new], state
  end

  def handle_playback_state_changed(_old, _new, state) do
    state |> PlaybackBuffer.eval
  end

  defp do_handle_message({type, args}, :info, state)
  when type in [:membrane_demand, :membrane_buffer, :membrane_caps, :membrane_event]
  do {type, args} |> PlaybackBuffer.store(state)
  end

  defp do_handle_message({:membrane_get_pad_full_name, args}, :call, state), do:
    forward(:get_pad_full_name, args, state)

  defp do_handle_message(:membrane_linking_finished, :call, state), do:
    forward(:handle_linking_finished, state)

  defp do_handle_message({:membrane_set_message_bus, args}, :call, state), do:
    forward(:handle_message_bus, args, state)

  defp do_handle_message({:membrane_set_controlling_pid, args}, :call, state), do:
    forward(:handle_controlling_pid, args, state)

  defp do_handle_message({:membrane_handle_link, args}, :call, state), do:
    forward(:handle_link, args, state)

  defp do_handle_message(:membrane_unlink, :call, state) do
    with :ok <- forward(:unlink, state),
    do: {:ok, state}
  end

  defp do_handle_message({:membrane_handle_unlink, args}, :call, state), do:
    forward(:handle_unlink, args, state)

  defp do_handle_message({:membrane_demand_in, args}, :call, state), do:
    forward(:handle_demand_in, args, state)

  defp do_handle_message({:membrane_self_demand, args}, :info, state), do:
    forward(:handle_self_demand, args, state)

  defp do_handle_message(other, :info, state), do:
    forward(:handle_message, other, state)

  defp forward(callback, args \\ [], %State{module: module} = state) do
    apply module.manager_module, callback, (args |> Helper.listify) ++ [state]
  end


end
