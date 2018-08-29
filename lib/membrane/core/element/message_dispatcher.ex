defmodule Membrane.Core.Element.MessageDispatcher do
  @moduledoc false
  # Module handling messages incoming to element and dispatching them to controllers.

  alias Membrane.Core
  alias Core.Element.{DemandHandler, LifecycleController, PadController, PlaybackBuffer, State}
  alias Core.PlaybackHandler
  use Core.Element.Log
  use Bunch

  @type message_t :: {atom, args :: any | list}

  @doc """
  Parses message incoming to element and forwards it to proper controller.
  """
  @spec handle_message(message_t, :info | :call | :other, State.t()) :: State.stateful_try_t()
  def handle_message(message, mode, state) do
    with {:ok, res} <- do_handle_message(message, mode, state) |> Bunch.stateful_try_with_status() do
      res
    else
      {_error, {{:error, reason}, state}} ->
        reason = {:cannot_handle_message, message: message, mode: mode, reason: reason}

        warn_error(
          """
          MessageDispatcher: cannot handle message: #{inspect(message)}, mode: #{inspect(mode)}
          """,
          reason,
          state
        )
    end
  end

  @spec do_handle_message(message_t, :info | :call | :other, State.t()) :: State.stateful_try_t()
  defp do_handle_message({:membrane_init, options}, :other, state) do
    LifecycleController.handle_init(options, state)
  end

  defp do_handle_message({:membrane_shutdown, reason}, :other, state) do
    LifecycleController.handle_shutdown(reason, state)
  end

  defp do_handle_message({:membrane_pipeline_down, reason}, :info, state) do
    LifecycleController.handle_pipeline_down(reason, state)
  end

  defp do_handle_message({:membrane_change_playback_state, [old, new]}, :info, state) do
    LifecycleController.handle_playback_state(old, new, state)
  end

  defp do_handle_message({:membrane_change_playback_state, new_playback_state}, :info, state) do
    PlaybackHandler.change_playback_state(new_playback_state, LifecycleController, state)
  end

  defp do_handle_message({:membrane_set_message_bus, message_bus}, :call, state) do
    LifecycleController.handle_message_bus(message_bus, state)
  end

  defp do_handle_message({:membrane_set_controlling_pid, pid}, :call, state) do
    LifecycleController.handle_controlling_pid(pid, state)
  end

  defp do_handle_message({:membrane_demand_in, [demand_in, pad_name]}, :call, state) do
    LifecycleController.handle_demand_in(demand_in, pad_name, state)
  end

  defp do_handle_message(:membrane_unlink, :call, state) do
    LifecycleController.unlink(state)
  end

  defp do_handle_message({:membrane_demand, [pad_name, source, type, size]}, :info, state) do
    DemandHandler.handle_demand(pad_name, source, type, size, state)
  end

  # incoming demands, buffers, caps, events from other element
  defp do_handle_message({type, args}, :info, state)
       when type in [:membrane_demand, :membrane_buffer, :membrane_caps, :membrane_event] do
    {type, args} |> PlaybackBuffer.store(state)
  end

  defp do_handle_message({:membrane_get_pad_full_name, pad_name}, :call, state) do
    PadController.get_pad_full_name(pad_name, state)
  end

  defp do_handle_message(:membrane_linking_finished, :call, state) do
    PadController.handle_linking_finished(state)
  end

  defp do_handle_message(
         {:membrane_handle_link, [pad_name, pad_direction, pid, other_name, props]},
         :call,
         state
       ) do
    PadController.handle_link(pad_name, pad_direction, pid, other_name, props, state)
  end

  defp do_handle_message({:membrane_handle_unlink, pad_name}, :call, state) do
    PadController.handle_unlink(pad_name, state)
  end

  defp do_handle_message(other, :info, state) do
    LifecycleController.handle_message(other, state)
  end
end
