defmodule Membrane.Element.Manager.MessageDispatcher do
  alias Membrane.Element
  alias Element.Manager.{Common, PlaybackBuffer}
  use Element.Manager.Log
  use Membrane.Helper

  def handle_message(message, mode, state) do
    with {:ok, res} <- do_handle_message(message, mode, state) |> Helper.result_with_status() do
      res
    else
      {_, {{:error, reason}, state}} ->
        reason = {:cannot_handle_message, message: message, mode: mode, reason: reason}

        warn_error(
          """
          MessageDispatcher: cannot handle message: #{inspect(message)}, mode: #{inspect(mode)}
          """,
          reason,
          state
        )

      {_, {:error, reason}} ->
        reason = {:cannot_handle_message, message: message, mode: mode, reason: reason}

        warn_error(
          """
          MessageDispatcher: cannot handle message: #{inspect(message)}, mode: #{inspect(mode)}
          """,
          reason,
          state
        )

        {{:error, reason}, state}
    end
  end

  def handle_playback_state(old, new, state) do
    forward(:handle_playback_state, [old, new], state)
  end

  def handle_playback_state_changed(_old, _new, state) do
    state |> PlaybackBuffer.eval()
  end

  defp do_handle_message({:membrane_change_playback_state, new_playback_state}, :info, state),
    do: Element.resolve_playback_change(new_playback_state, state)

  defp do_handle_message({type, args}, :info, state)
       when type in [:membrane_demand, :membrane_buffer, :membrane_caps, :membrane_event] do
    {type, args} |> PlaybackBuffer.store(state)
  end

  defp do_handle_message({:membrane_get_pad_full_name, args}, :call, state),
    do: forward(:get_pad_full_name, args, state)

  defp do_handle_message(:membrane_linking_finished, :call, state),
    do: forward(:handle_linking_finished, state)

  defp do_handle_message({:membrane_set_message_bus, args}, :call, state),
    do: forward(:handle_message_bus, args, state)

  defp do_handle_message({:membrane_set_controlling_pid, args}, :call, state),
    do: forward(:handle_controlling_pid, args, state)

  defp do_handle_message({:membrane_handle_link, args}, :call, state),
    do: forward(:handle_link, args, state)

  defp do_handle_message(:membrane_unlink, :call, state) do
    with :ok <- forward(:unlink, state), do: {:ok, state}
  end

  defp do_handle_message({:membrane_handle_unlink, args}, :call, state),
    do: forward(:handle_unlink, args, state)

  defp do_handle_message({:membrane_demand_in, args}, :call, state),
    do: forward(:handle_demand_in, args, state)

  defp do_handle_message({:membrane_self_demand, args}, :info, state),
    do: forward(:handle_self_demand, args, state)

  defp do_handle_message(other, :info, state), do: forward(:handle_message, other, state)

  defp forward(callback, args \\ [], state) do
    apply(Common, callback, (args |> Helper.listify()) ++ [state])
  end
end
