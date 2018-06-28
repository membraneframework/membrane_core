defmodule Membrane.Core.Element.MessageDispatcher do
  alias Membrane.{Core, Element}
  alias Core.Element.{Common, LifecycleController, PlaybackBuffer}
  use Core.Element.Log
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

  defp do_handle_message({:membrane_init, options}, :other, state) do
    LifecycleController.handle_init(options, state)
  end

  defp do_handle_message({:membrane_shutdown, reason}, :other, state) do
    LifecycleController.handle_shutdown(reason, state)
  end

  defp do_handle_message({:membrane_pipeline_down, reason}, :info, state),
    do: LifecycleController.handle_pipeline_down(reason, state)

  defp do_handle_message({:membrane_change_playback_state, [old, new]}, :other, state) do
    LifecycleController.handle_playback_state(old, new, state)
  end

  defp do_handle_message({:membrane_playback_state_changed, [_old, _new]}, :other, state) do
    state |> PlaybackBuffer.eval()
  end

  defp do_handle_message({:membrane_change_playback_state, new_playback_state}, :info, state),
    do: Element.resolve_playback_change(new_playback_state, state)

  defp do_handle_message({:membrane_set_message_bus, message_bus}, :call, state),
    do: LifecycleController.handle_message_bus(message_bus, state)

  defp do_handle_message({:membrane_set_controlling_pid, pid}, :call, state),
    do: LifecycleController.handle_controlling_pid(pid, state)

  defp do_handle_message({:membrane_demand_in, [demand_in, pad_name]}, :call, state),
    do: LifecycleController.handle_demand_in(demand_in, pad_name, state)

  defp do_handle_message({type, args}, :info, state)
       when type in [:membrane_demand, :membrane_buffer, :membrane_caps, :membrane_event] do
    {type, args} |> PlaybackBuffer.store(state)
  end

  defp do_handle_message({:membrane_get_pad_full_name, args}, :call, state),
    do: forward(:get_pad_full_name, args, state)

  defp do_handle_message(:membrane_linking_finished, :call, state),
    do: forward(:handle_linking_finished, state)

  defp do_handle_message({:membrane_handle_link, args}, :call, state),
    do: forward(:handle_link, args, state)

  defp do_handle_message(:membrane_unlink, :call, state) do
    with :ok <- forward(:unlink, state), do: {:ok, state}
  end

  defp do_handle_message({:membrane_handle_unlink, args}, :call, state),
    do: forward(:handle_unlink, args, state)

  defp do_handle_message({:membrane_self_demand, args}, :info, state),
    do: forward(:handle_self_demand, args, state)

  defp do_handle_message(other, :info, state),
    do: LifecycleController.handle_message(other, state)

  defp forward(callback, args \\ [], state) do
    apply(Common, callback, (args |> Helper.listify()) ++ [state])
  end
end
