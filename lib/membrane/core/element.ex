defmodule Membrane.Core.Element do
  @moduledoc false

  # Module containing functions spawning, shutting down, inspecting and controlling
  # playback of elements. These functions are usually called by `Membrane.Pipeline`
  # or `Membrane.Bin`.
  #
  # Modules in this namespace are responsible for managing elements: handling incoming
  # data, executing callbacks and evaluating actions. These modules can be divided
  # in terms of functionality in the following way:
  # - Controllers handle messages received from other elements or calls from other
  #   controllers and handlers
  # - Handlers handle actions invoked by element itself
  # - Models contain some utility functions for accessing data in state
  # - `Membrane.Core.Element.State` defines the state struct that these modules
  #   operate on.

  use Bunch
  use GenServer

  alias Membrane.{Clock, Core, ResourceGuard, Sync}
  alias Membrane.Core.Child.PadSpecHandler

  alias Membrane.Core.Element.{
    BufferController,
    DemandController,
    DiamondDetectionController,
    EffectiveFlowController,
    EventController,
    LifecycleController,
    ManualFlowController,
    PadController,
    State,
    StreamFormatController
  }

  alias Membrane.Core.{SubprocessSupervisor, TimerController}

  require Membrane.Core.Utils, as: Utils
  require Membrane.Core.Message, as: Message
  require Membrane.Core.Stalker, as: Stalker
  require Membrane.Core.Telemetry, as: Telemetry
  require Membrane.Core.LegacyTelemetry, as: LegacyTelemetry
  require Membrane.Logger

  @type options :: %{
          module: module(),
          name: Membrane.Element.name(),
          node: node() | nil,
          user_options: Membrane.Element.options(),
          sync: Sync.t(),
          parent: pid(),
          parent_clock: Clock.t(),
          parent_path: Membrane.ComponentPath.path(),
          log_metadata: Logger.metadata(),
          subprocess_supervisor: pid(),
          parent_supervisor: pid()
        }

  @doc """
  Starts process for element of given module, initialized with given options and
  links it to the current process in the supervision tree.

  Calls `GenServer.start_link/3` underneath.
  """
  @spec start_link(options) :: GenServer.on_start()
  def start_link(options),
    do: do_start(:start_link, options)

  @doc """
  Works similarly to `start_link/3`, but does not link to the current process.
  """
  @spec start(options) :: GenServer.on_start()
  def start(options),
    do: do_start(:start, options)

  defp do_start(method, options) do
    %{module: module, name: name, node: node, user_options: user_options} = options

    Membrane.Logger.debug("""
    Element #{method}: #{inspect(name)}
    node: #{node},
    module: #{inspect(module)},
    element options: #{inspect(user_options)},
    method: #{method}
    """)

    # rpc if necessary
    if node do
      result = :rpc.call(node, GenServer, :start, [__MODULE__, options])
      _ignored = with {:start_link, {:ok, pid}} <- {method, result}, do: Process.link(pid)
      result
    else
      apply(GenServer, method, [__MODULE__, options])
    end
  end

  @impl GenServer
  def init(options) do
    Utils.log_on_error do
      do_init(options)
    end
  end

  # Suppress false positive dialyzer warnings
  # https://github.com/elixir-lang/elixir/issues/14576
  @dialyzer {:nowarn_function, do_init: 1}
  defp do_init(options) do
    Process.link(options.parent_supervisor)

    observability_config = %{
      name: options.name,
      component_type: :element,
      pid: self(),
      parent_path: options.parent_path,
      log_metadata: options.log_metadata
    }

    Membrane.Core.Stalker.register_component(options.stalker, observability_config)
    SubprocessSupervisor.set_parent_component(options.subprocess_supervisor, observability_config)

    {:ok, resource_guard} =
      SubprocessSupervisor.start_utility(options.subprocess_supervisor, {ResourceGuard, self()})

    LegacyTelemetry.report_init(:element)
    ResourceGuard.register(resource_guard, fn -> LegacyTelemetry.report_terminate(:element) end)

    self_pid = self()

    Stalker.register_metric_function(:message_queue_length, fn ->
      case Process.info(self_pid, :message_queue_len) do
        {:message_queue_len, len} -> len
        nil -> 0
      end
    end)

    Stalker.register_metric_function(:total_reductions, fn ->
      case Process.info(self_pid, :reductions) do
        {:reductions, reductions} -> reductions
        nil -> 0
      end
    end)

    state =
      %State{
        module: options.module,
        name: options.name,
        parent_pid: options.parent,
        type: options.module.membrane_element_type(),
        synchronization: %{
          parent_clock: options.parent_clock,
          timers: %{},
          clock: nil,
          stream_sync: options.sync,
          latency: 0
        },
        resource_guard: resource_guard,
        subprocess_supervisor: options.subprocess_supervisor,
        stalker: options.stalker
      }
      |> PadSpecHandler.init_pads()

    state = LifecycleController.handle_init(options.user_options, state)
    {:ok, state, {:continue, :setup}}
  end

  @impl GenServer
  def handle_continue(:setup, state) do
    Utils.log_on_error do
      state = LifecycleController.handle_setup(state)
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call(request, from, state) do
    Utils.log_on_error do
      do_handle_call(request, from, state)
    end
  end

  defp do_handle_call(Message.new(:get_clock), _from, state) do
    {:reply, state.synchronization.clock, state}
  end

  defp do_handle_call(
         Message.new(:handle_link, [direction, this, other, params]),
         _from,
         state
       ) do
    {reply, state} = PadController.handle_link(direction, this, other, params, state)
    {:reply, reply, state}
  end

  defp do_handle_call(Message.new(:set_stream_sync, sync), _from, state) do
    state = put_in(state.synchronization.stream_sync, sync)
    {:reply, :ok, state}
  end

  defp do_handle_call(Message.new(:get_child_pid, _child_name), _from, state) do
    {:reply, {:error, :element_cannot_have_children}, state}
  end

  defp do_handle_call(message, {pid, _tag}, _state) do
    raise Membrane.ElementError,
          "Received invalid message #{inspect(message)} from #{inspect(pid)}"
  end

  @impl GenServer
  def handle_info(message, state) do
    Utils.log_on_error do
      Telemetry.report_queue_len(self())

      do_handle_info(message, state)
    end
  end

  @compile {:inline, do_handle_info: 2}

  defp do_handle_info(Message.new(:atomic_demand_increased, pad_ref), state) do
    state = DemandController.snapshot_atomic_demand(pad_ref, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:resume_delayed_demands_loop), state) do
    state = ManualFlowController.resume_delayed_demands_loop(state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:buffer, buffers, _opts) = msg, state) do
    pad_ref = Message.for_pad(msg)
    state = BufferController.handle_incoming_buffers(pad_ref, buffers, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:stream_format, stream_format, _opts) = msg, state) do
    pad_ref = Message.for_pad(msg)
    state = StreamFormatController.handle_stream_format(pad_ref, stream_format, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:event, event, _opts) = msg, state) do
    pad_ref = Message.for_pad(msg)
    state = EventController.handle_event(pad_ref, event, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:play), state) do
    state = LifecycleController.handle_playing(state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:handle_unlink, pad_ref), state) do
    state = PadController.handle_unlink(pad_ref, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:timer_tick, timer_id), state) do
    state = TimerController.handle_tick(timer_id, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:parent_notification, notification), state) do
    state = Core.Child.LifecycleController.handle_parent_notification(notification, state)
    {:noreply, state}
  end

  defp do_handle_info(
         Message.new(:sender_effective_flow_control_resolved, [
           input_pad_ref,
           effective_flow_control
         ]),
         state
       ) do
    state =
      EffectiveFlowController.handle_sender_effective_flow_control(
        input_pad_ref,
        effective_flow_control,
        state
      )

    {:noreply, state}
  end

  defp do_handle_info(Message.new(:diamond_detection, message), state) do
    state = DiamondDetectionController.handle_diamond_detection_message(message, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:terminate), state) do
    state = LifecycleController.handle_terminate_request(state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(_type, _args, _opts) = message, _state) do
    raise Membrane.ElementError, "Received invalid message #{inspect(message)}"
  end

  defp do_handle_info({:membrane_clock_ratio, clock, ratio}, state) do
    state = TimerController.handle_clock_update(clock, ratio, state)
    {:noreply, state}
  end

  defp do_handle_info(message, state) do
    state = LifecycleController.handle_info(message, state)
    {:noreply, state}
  end
end
