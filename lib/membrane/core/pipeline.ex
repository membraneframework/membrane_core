defmodule Membrane.Core.Pipeline do
  @moduledoc false
  use GenServer

  alias __MODULE__.{ActionHandler, State}
  alias Membrane.{Clock, ResourceGuard}
  alias Membrane.Core.{CallbackHandler, SubprocessSupervisor}
  alias Membrane.Core.Parent.{ChildLifeController, LifecycleController}
  alias Membrane.Core.TimerController
  alias Membrane.Pipeline.CallbackContext

  require Membrane.Core.Message, as: Message
  require Membrane.Core.Telemetry, as: Telemetry
  require Membrane.Logger
  require Membrane.Core.Component
  require Membrane.Pipeline.CallbackContext.Call

  @impl GenServer
  def init(params) do
    observability_config = %{name: params.name, component_type: :pipeline, pid: self()}
    Membrane.Core.Observability.setup(observability_config)
    SubprocessSupervisor.set_parent_component(params.subprocess_supervisor, observability_config)

    {:ok, resource_guard} =
      SubprocessSupervisor.start_utility(params.subprocess_supervisor, {ResourceGuard, self()})

    Telemetry.report_init(:pipeline)

    ResourceGuard.register(resource_guard, fn ->
      Telemetry.report_terminate(:pipeline)
    end)

    {:ok, clock} = Clock.start_link(proxy: true)

    state = %State{
      module: params.module,
      synchronization: %{
        clock_proxy: clock,
        clock_provider: %{clock: nil, provider: nil, choice: :auto},
        timers: %{}
      },
      subprocess_supervisor: params.subprocess_supervisor,
      resource_guard: resource_guard
    }

    require CallbackContext.Init

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_init,
        ActionHandler,
        %{context: &CallbackContext.Init.from_state/1},
        [],
        %{state | internal_state: params.options}
      )

    {:ok, state, {:continue, :setup}}
  end

  @impl GenServer
  def handle_continue(:setup, state) do
    state = LifecycleController.handle_setup(state)
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
  def handle_info(Message.new(:link_response, [link_id, direction]), state) do
    state = ChildLifeController.handle_link_response(link_id, direction, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:initialized, child), state) do
    state = ChildLifeController.handle_child_initialized(child, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:child_death, [name, reason]), state) do
    {result, state} = ChildLifeController.handle_child_death(name, reason, state)

    case result do
      :stop -> {:stop, :normal, state}
      :continue -> {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(Message.new(:terminate), state) do
    state = LifecycleController.handle_terminate_request(state)
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
  def handle_info(message, state) do
    state = LifecycleController.handle_info(message, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(message, from, state) do
    context = &CallbackContext.Call.from_state(&1, from: from)

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_call,
        Membrane.Core.Pipeline.ActionHandler,
        %{context: context},
        [message],
        state
      )

    {:noreply, state}
  end
end
