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
    withl handle:
            {:ok, {res, state}} <-
              do_handle_message(message, mode, state) |> Bunch.stateful_try_with_status(),
          demands: {:ok, state} <- DemandHandler.handle_delayed_demands(state) do
      {res, state}
    else
      handle: {_error, {{:error, reason}, state}} ->
        handle_message_error(message, mode, reason, state)

      demands: {{:error, reason}, state} ->
        handle_message_error(message, mode, reason, state)
    end
  end

  @spec do_handle_message(message_t, :info | :call | :other, State.t()) ::
          State.stateful_try_t() | State.statefu_try_t(any)
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

  defp do_handle_message({:membrane_demand_unit, [demand_unit, pad_ref]}, :call, state) do
    LifecycleController.handle_demand_unit(demand_unit, pad_ref, state)
  end

  defp do_handle_message(:membrane_unlink, :call, state) do
    LifecycleController.unlink(state)
  end

  # Sent by `Membrane.Core.Element.ActionHandler.handle_demand`, check there for
  # more information
  defp do_handle_message({:membrane_invoke_supply_demand, pad_ref}, :info, state) do
    DemandHandler.supply_demand(pad_ref, state)
  end

  # incoming demands, buffers, caps, events from other element
  defp do_handle_message({type, args}, :info, state)
       when type in [:membrane_demand, :membrane_buffer, :membrane_caps, :membrane_event] do
    {type, args} |> PlaybackBuffer.store(state)
  end

  defp do_handle_message({:membrane_get_pad_ref, pad_name}, :call, state) do
    PadController.get_pad_ref(pad_name, state)
  end

  defp do_handle_message(:membrane_linking_finished, :call, state) do
    PadController.handle_linking_finished(state)
  end

  defp do_handle_message(
         {:membrane_handle_link, [pad_ref, pad_direction, pid, other_ref, props]},
         :call,
         state
       ) do
    PadController.handle_link(pad_ref, pad_direction, pid, other_ref, props, state)
  end

  defp do_handle_message({:membrane_handle_unlink, pad_ref}, :call, state) do
    PadController.handle_unlink(pad_ref, state)
  end

  defp do_handle_message(other, :info, state) do
    LifecycleController.handle_message(other, state)
  end

  defp handle_message_error(message, mode, reason, state) do
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
