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

  alias Membrane.Core.{SubprocessSupervisor, TimerController}

  alias Membrane.Core.Element.{
    BufferController,
    DemandController,
    EventController,
    LifecycleController,
    PadController,
    State,
    StreamFormatController
  }

  require Membrane.Core.Message, as: Message
  require Membrane.Core.Telemetry, as: Telemetry
  require Membrane.Logger

  @type options_t :: %{
          module: module,
          name: Membrane.Element.name_t(),
          node: node | nil,
          user_options: Membrane.Element.options_t(),
          sync: Sync.t(),
          parent: pid,
          parent_clock: Clock.t(),
          parent_path: Membrane.ComponentPath.path_t(),
          log_metadata: Logger.metadata(),
          subprocess_supervisor: pid(),
          parent_supervisor: pid()
        }

  @doc """
  Starts process for element of given module, initialized with given options and
  links it to the current process in the supervision tree.

  Calls `GenServer.start_link/3` underneath.
  """
  @spec start_link(options_t) :: GenServer.on_start()
  def start_link(options),
    do: do_start(:start_link, options)

  @doc """
  Works similarly to `start_link/3`, but does not link to the current process.
  """
  @spec start(options_t) :: GenServer.on_start()
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

      # TODO: use an atomic way of linking once https://github.com/erlang/otp/issues/6375 is solved
      with {:start_link, {:ok, pid}} <- {method, result}, do: Process.link(pid)
      result
    else
      apply(GenServer, method, [__MODULE__, options])
    end
  end

  @impl GenServer
  def init(options) do
    Process.link(options.parent_supervisor)

    observability_config = %{
      name: options.name,
      component_type: :bin,
      pid: self(),
      parent_path: options.parent_path,
      log_metadata: options.log_metadata
    }

    Membrane.Core.Observability.setup(observability_config)
    SubprocessSupervisor.set_parent_component(options.subprocess_supervisor, observability_config)

    {:ok, resource_guard} =
      SubprocessSupervisor.start_utility(options.subprocess_supervisor, {ResourceGuard, self()})

    Telemetry.report_init(:element)

    ResourceGuard.register(resource_guard, fn -> Telemetry.report_terminate(:element) end)

    state =
      Map.take(options, [:module, :name, :parent_clock, :sync, :parent, :subprocess_supervisor])
      |> Map.put(:resource_guard, resource_guard)
      |> State.new()

    state = LifecycleController.handle_init(options.user_options, state)
    {:ok, state, {:continue, :setup}}
  end

  @impl GenServer
  def handle_continue(:setup, state) do
    state = LifecycleController.handle_setup(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(Message.new(:get_clock), _from, state) do
    {:reply, state.synchronization.clock, state}
  end

  @impl GenServer
  def handle_call(
        Message.new(:handle_link, [direction, this, other, params]),
        _from,
        state
      ) do
    {reply, state} = PadController.handle_link(direction, this, other, params, state)
    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(Message.new(:set_stream_sync, sync), _from, state) do
    state = put_in(state.synchronization.stream_sync, sync)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(message, {pid, _tag}, _state) do
    raise Membrane.ElementError,
          "Received invalid message #{inspect(message)} from #{inspect(pid)}"
  end

  @impl GenServer
  def handle_info(message, state) do
    Telemetry.report_metric(
      :queue_len,
      :erlang.process_info(self(), :message_queue_len) |> elem(1)
    )

    do_handle_info(message, state)
  end

  @compile {:inline, do_handle_info: 2}

  defp do_handle_info(Message.new(:demand, size, _opts) = msg, state) do
    pad_ref = Message.for_pad(msg)
    state = DemandController.handle_demand(pad_ref, size, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:buffer, buffers, _opts) = msg, state) do
    pad_ref = Message.for_pad(msg)
    state = BufferController.handle_buffer(pad_ref, buffers, state)
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
