defmodule Membrane.Core.Pipeline do
  @moduledoc false
  use GenServer

  alias __MODULE__.{ActionHandler, State}
  alias Membrane.Clock
  alias Membrane.Core.CallbackHandler
  alias Membrane.Core.Parent.{ChildLifeController, LifecycleController}
  alias Membrane.Core.TimerController
  alias Membrane.Pipeline.CallbackContext

  require Membrane.Core.Message, as: Message
  require Membrane.Core.Telemetry, as: Telemetry
  require Membrane.Logger
  require Membrane.Core.Component
  require Membrane.Pipeline.CallbackContext.Call

  @impl GenServer
  def init({module, pipeline_options}) do
    pipeline_name = "pipeline@#{:erlang.pid_to_list(self())}"
    :ok = Membrane.ComponentPath.set([pipeline_name])
    :ok = Membrane.Logger.set_prefix(pipeline_name)

    Telemetry.report_init(:pipeline)

    {:ok, clock} = Clock.start_link(proxy: true)

    state = %State{
      module: module,
      synchronization: %{
        clock_proxy: clock,
        clock_provider: %{clock: nil, provider: nil, choice: :auto},
        timers: %{}
      }
    }

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_init,
        ActionHandler,
        %{state: false},
        [pipeline_options],
        state
      )

    {:ok, state, {:continue, :init}}
  end

  @impl GenServer
  def handle_continue(:init, state) do
    state = LifecycleController.handle_setup(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        Message.new(:playback_state_changed, [pid, new_playback_state]),
        state
      ) do
    state = ChildLifeController.child_playback_changed(pid, new_playback_state, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:change_playback_state, new_state), state) do
    state = LifecycleController.change_playback_state(new_state, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:stream_management_event, [element_name, pad_ref, event]), state) do
    state =
      LifecycleController.handle_stream_management_event(event, element_name, pad_ref, state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:child_notification, [from, notification]), state) do
    state = LifecycleController.handle_child_notification(from, notification, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:timer_tick, timer_id), state) do
    state = TimerController.handle_tick(timer_id, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:link_response, link_id), state) do
    state = ChildLifeController.LinkHandler.handle_link_response(link_id, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:spec_linking_timeout, spec_ref), state) do
    state = ChildLifeController.handle_spec_timeout(spec_ref, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:initialized, child), state) do
    state = ChildLifeController.handle_child_initialized(child, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(_type, _args, _opts) = message, _state) do
    raise Membrane.PipelineError, "Received invalid message #{inspect(message)}"
  end

  @impl GenServer
  def handle_info({:membrane_clock_ratio, clock, ratio}, state) do
    state = TimerController.handle_clock_update(clock, ratio, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason} = message, state) do
    if is_child_pid?(pid, state) do
      state = ChildLifeController.handle_child_death(pid, reason, state)
      {:noreply, state}
    else
      state = LifecycleController.handle_info(message, state)
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(message, state) do
    state = LifecycleController.handle_info(message, state)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Telemetry.report_terminate(:pipeline)
    :ok = state.module.handle_shutdown(reason, state.internal_state)
  end

  @impl GenServer
  def handle_call(message, from, state) do
    context = &CallbackContext.Call.from_state(&1, from: from)

    CallbackHandler.exec_and_handle_callback(
      :handle_call,
      Membrane.Core.Pipeline.ActionHandler,
      %{context: context},
      [message],
      state
    )

    {:noreply, state}
  end

  defp is_child_pid?(pid, state) do
    Enum.any?(state.children, fn {_name, entry} -> entry.pid == pid end)
  end
end
