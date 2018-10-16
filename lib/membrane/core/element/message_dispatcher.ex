defmodule Membrane.Core.Element.MessageDispatcher do
  @moduledoc false
  # Module handling messages incoming to element and dispatching them to controllers.

  alias Membrane.Core
  alias Core.Element.{DemandHandler, LifecycleController, PadController, PlaybackBuffer, State}
  alias Core.{Message, PlaybackHandler}
  require Message
  use Core.Element.Log
  use Bunch

  @doc """
  Parses message incoming to element and forwards it to proper controller.
  """
  @spec handle_message(Message.t(), :info | :call | :other, State.t()) :: State.stateful_try_t()
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

  @spec do_handle_message(Message.t(), :info | :call | :other, State.t()) ::
          State.stateful_try_t()
  defp do_handle_message(Message.new(:init, options), :other, state) do
    LifecycleController.handle_init(options, state)
  end

  defp do_handle_message(Message.new(:shutdown, reason), :other, state) do
    LifecycleController.handle_shutdown(reason, state)
  end

  defp do_handle_message(Message.new(:pipeline_down, reason), :info, state) do
    LifecycleController.handle_pipeline_down(reason, state)
  end

  defp do_handle_message(Message.new(:change_playback_state, new_playback_state), :info, state) do
    PlaybackHandler.change_playback_state(new_playback_state, LifecycleController, state)
  end

  defp do_handle_message(Message.new(:set_watcher, watcher), :call, state) do
    LifecycleController.handle_watcher(watcher, state)
  end

  defp do_handle_message(Message.new(:set_controlling_pid, pid), :call, state) do
    LifecycleController.handle_controlling_pid(pid, state)
  end

  defp do_handle_message(Message.new(:demand_unit, [demand_unit, pad_ref]), :call, state) do
    LifecycleController.handle_demand_unit(demand_unit, pad_ref, state)
  end

  defp do_handle_message(Message.new(:unlink), :call, state) do
    LifecycleController.unlink(state)
  end

  # Sent by `Membrane.Core.Element.ActionHandler.handle_demand`, check there for
  # more information
  defp do_handle_message(Message.new(:invoke_supply_demand, pad_ref), :info, state) do
    DemandHandler.supply_demand(pad_ref, state)
  end

  # incoming demands, buffers, caps, events from other element
  defp do_handle_message(Message.new(type, args), :info, state)
       when type in [:demand, :buffer, :caps, :event] do
    {type, args} |> PlaybackBuffer.store(state)
  end

  defp do_handle_message(Message.new(:get_pad_ref, pad_name), :call, state) do
    PadController.get_pad_ref(pad_name, state)
  end

  defp do_handle_message(Message.new(:linking_finished), :call, state) do
    PadController.handle_linking_finished(state)
  end

  defp do_handle_message(
         Message.new(:handle_link, [pad_ref, pad_direction, pid, other_ref, props]),
         :call,
         state
       ) do
    PadController.handle_link(pad_ref, pad_direction, pid, other_ref, props, state)
  end

  defp do_handle_message(Message.new(:handle_unlink, pad_ref), :call, state) do
    PadController.handle_unlink(pad_ref, state)
  end

  defp do_handle_message(Message.new(_, _) = message, mode, state) do
    {{:error, {:invalid_message, message, mode: mode}}, state}
  end

  defp do_handle_message(message, :info, state) do
    LifecycleController.handle_other(message, state)
  end

  defp do_handle_message(message, mode, state) do
    {{:error, {:invalid_message, message, mode: mode}}, state}
  end
end
