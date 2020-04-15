defmodule Membrane.Core.Element.MessageDispatcher do
  @moduledoc false

  # Module handling messages incoming to element and dispatching them to controllers.

  alias Membrane.Core

  alias Core.Child.PadController

  alias Core.Element.{
    DemandHandler,
    LifecycleController,
    PlaybackBuffer,
    State,
    TimerController
  }

  alias Core.{Child, Message, PlaybackHandler}
  alias Membrane.Helper
  require Message
  import Helper.GenServer
  use Core.Element.Log
  use Bunch

  @doc """
  Parses message incoming to element and forwards it to proper controller.
  """
  @spec handle_message(Message.t(), :info | :call | :other, State.t()) ::
          State.stateful_try_t()
          | State.stateful_try_t(any)
          | Helper.GenServer.genserver_return_t()
  def handle_message(message, mode, state) do
    result =
      withl handle:
              {:ok, {res, state}} <-
                message |> do_handle_message(mode, state) |> Bunch.stateful_try_with_status(),
            demands: {:ok, state} <- DemandHandler.handle_delayed_demands(state) do
        {res, state}
      else
        handle: {_error, {{:error, reason}, state}} ->
          handle_message_error(message, mode, reason, state)

        demands: {{:error, reason}, state} ->
          handle_message_error(message, mode, reason, state)
      end

    # TODO get rid of this hack when we resign from
    # Bunch.stateful_try_with and family. This hack unwraps
    # gensever :stop tuple.
    case result do
      {{:ok, {:stop, _reason, _state} = stop}, state} ->
        stop |> noreply(state)

      _ ->
        case mode do
          :info -> result |> noreply(state)
          :call -> result |> reply(state)
          :other -> result
        end
    end
  end

  @spec do_handle_message(Message.t(), :info | :call | :other, State.t()) ::
          State.stateful_try_t() | State.stateful_try_t(any)
  defp do_handle_message(Message.new(:init, options), :other, state) do
    LifecycleController.handle_init(options, state)
  end

  defp do_handle_message(Message.new(:shutdown, reason), :other, state) do
    LifecycleController.handle_shutdown(reason, state)
  end

  defp do_handle_message(Message.new(:pipeline_down, reason), :info, state) do
    LifecycleController.handle_pipeline_down(reason, state)
  end

  defp do_handle_message(
         Message.new(:change_playback_state, new_playback_state),
         :info,
         state
       ) do
    PlaybackHandler.change_playback_state(new_playback_state, LifecycleController, state)
  end

  defp do_handle_message(Message.new(:handle_watcher, watcher), :call, state) do
    Child.LifecycleController.handle_watcher(watcher, state)
  end

  defp do_handle_message(Message.new(:set_controlling_pid, pid), :call, state) do
    Child.LifecycleController.handle_controlling_pid(pid, state)
  end

  defp do_handle_message(Message.new(:demand_unit, [demand_unit, pad_ref]), :info, state) do
    Child.LifecycleController.handle_demand_unit(demand_unit, pad_ref, state)
  end

  defp do_handle_message(Message.new(:terminate), :info, state) do
    LifecycleController.terminate(state)
  end

  defp do_handle_message(Message.new(:terminate_and_kill), :info, state) do
    LifecycleController.terminate(state, kill_after?: true)
  end

  # Sent by `Membrane.Core.Element.DemandHandler.handle_delayed_demands`, check there for
  # more information
  defp do_handle_message(Message.new(:invoke_supply_demand, pad_ref), :info, state) do
    DemandHandler.supply_demand(pad_ref, state)
  end

  # incoming demands, buffers, caps, events from other element
  defp do_handle_message(Message.new(type, _args, _opts) = msg, :info, state)
       when type in [:demand, :buffer, :caps, :event] do
    msg |> PlaybackBuffer.store(state)
  end

  defp do_handle_message(Message.new(:linking_finished), :call, state) do
    PadController.handle_linking_finished(state)
  end

  defp do_handle_message(Message.new(:push_mode_announcment, [], for_pad: ref), :info, state) do
    PadController.enable_toilet_if_pull(ref, state)
  end

  defp do_handle_message(
         Message.new(:handle_link, [pad_ref, pad_direction, pid, other_ref, other_info, props]),
         :call,
         state
       ) do
    PadController.handle_link(pad_ref, pad_direction, pid, other_ref, other_info, props, state)
  end

  defp do_handle_message(Message.new(:handle_unlink, pad_ref), :info, state) do
    PadController.handle_unlink(pad_ref, state)
  end

  defp do_handle_message(Message.new(:timer_tick, timer_id), :info, state) do
    TimerController.handle_tick(timer_id, state)
  end

  defp do_handle_message({:membrane_clock_ratio, clock, ratio}, :info, state) do
    TimerController.handle_clock_update(clock, ratio, state)
  end

  defp do_handle_message(Message.new(:set_stream_sync, sync), :call, state) do
    new_state = put_in(state.synchronization.stream_sync, sync)
    {:ok, new_state}
  end

  defp do_handle_message(Message.new(_, _, _) = message, mode, state) do
    {{:error, {:invalid_message, message, mode: mode}}, state}
  end

  defp do_handle_message(message, :info, state) do
    LifecycleController.handle_other(message, state)
  end

  defp do_handle_message(message, mode, state) do
    {{:error, {:invalid_message, message, mode: mode}}, state}
  end

  defp handle_message_error(message, mode, reason, state) do
    reason = {:cannot_handle_message, reason, message: message, mode: mode}

    warn_error(
      """
      MessageDispatcher: cannot handle message: #{inspect(message)}, mode: #{inspect(mode)}
      """,
      reason,
      state
    )
  end
end
