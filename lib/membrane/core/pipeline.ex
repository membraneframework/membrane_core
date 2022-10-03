defmodule Membrane.Core.Pipeline do
  @moduledoc false
  use GenServer

  alias __MODULE__.{ActionHandler, State}
  alias Membrane.Clock
  alias Membrane.Core.{CallbackHandler, ChildrenSupervisor}
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
    ChildrenSupervisor.set_parent_component(params.children_supervisor, observability_config)
    Telemetry.report_init(:pipeline)

    {:ok, resource_guard} =
      ChildrenSupervisor.start_utility(
        params.children_supervisor,
        {Membrane.ResourceGuard, self()}
      )

    {:ok, clock} = Clock.start_link(proxy: true)

    state = %State{
      module: params.module,
      synchronization: %{
        clock_proxy: clock,
        clock_provider: %{clock: nil, provider: nil, choice: :auto},
        timers: %{}
      },
      children_supervisor: params.children_supervisor,
      resource_guard: resource_guard
    }

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_init,
        ActionHandler,
        %{state: false},
        [params.options],
        state
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
  def handle_info(Message.new(:link_response, link_id), state) do
    state = ChildLifeController.handle_link_response(link_id, state)
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

    CallbackHandler.exec_and_handle_callback(
      :handle_call,
      Membrane.Core.Pipeline.ActionHandler,
      %{context: context},
      [message],
      state
    )

    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    Telemetry.report_terminate(:pipeline)
  end
end
