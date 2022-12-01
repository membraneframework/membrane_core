defmodule Membrane.Core.Bin do
  @moduledoc false
  use Bunch
  use GenServer

  alias __MODULE__.{ActionHandler, PadController, State}
  alias Membrane.Bin.CallbackContext

  alias Membrane.Core.{
    CallbackHandler,
    Child,
    Message,
    Parent,
    SubprocessSupervisor,
    Telemetry,
    TimerController
  }

  alias Membrane.ResourceGuard

  require Membrane.Core.Message
  require Membrane.Core.Telemetry
  require Membrane.Logger

  @type options_t :: %{
          name: atom,
          module: module,
          node: node | nil,
          parent: pid,
          user_options: Membrane.Bin.options_t(),
          parent_clock: Membrane.Clock.t(),
          parent_path: Membrane.ComponentPath.path_t(),
          log_metadata: Logger.metadata(),
          sync: :membrane_no_sync,
          subprocess_supervisor: pid(),
          parent_supervisor: pid()
        }
  @doc """
  Starts the Bin based on given module and links it to the current
  process.

  Bin options are passed to module's `c:Membrane.Bin.handle_init/2` callback.

  Process options are internally passed to `GenServer.start_link/3`.

  Returns the same values as `GenServer.start_link/3`.
  """
  @spec start_link(options_t) :: GenServer.on_start()
  def start_link(options),
    do: do_start(:start_link, options)

  @doc """
  Works similarly to `start_link/3`, but does not link to the current process.
  """

  @spec start(options_t()) :: GenServer.on_start()
  def start(options),
    do: do_start(:start, options)

  defp do_start(method, options) do
    %{module: module, name: name, node: node, user_options: user_options} = options

    Membrane.Logger.debug("""
    Bin #{method}: #{inspect(name)}
    node: #{node},
    module: #{inspect(module)},
    bin options: #{inspect(user_options)}
    """)

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
    %{name: name, module: module} = options

    observability_config = %{
      name: name,
      component_type: :bin,
      pid: self(),
      parent_path: options.parent_path,
      log_metadata: options.log_metadata
    }

    Membrane.Core.Observability.setup(observability_config)
    SubprocessSupervisor.set_parent_component(options.subprocess_supervisor, observability_config)

    clock_proxy = Membrane.Clock.start_link(proxy: true) ~> ({:ok, pid} -> pid)
    clock = if Bunch.Module.check_behaviour(module, :membrane_clock?), do: clock_proxy, else: nil
    Message.send(options.parent, :clock, [name, clock])

    {:ok, resource_guard} =
      SubprocessSupervisor.start_utility(options.subprocess_supervisor, {ResourceGuard, self()})

    Telemetry.report_init(:bin)
    ResourceGuard.register(resource_guard, fn -> Telemetry.report_terminate(:bin) end)

    state =
      %State{
        module: module,
        name: name,
        parent_pid: options.parent,
        synchronization: %{
          parent_clock: options.parent_clock,
          timers: %{},
          clock: clock,
          clock_provider: %{clock: nil, provider: nil, choice: :auto},
          clock_proxy: clock_proxy,
          # This is a sync for siblings. This is not yet allowed.
          stream_sync: Membrane.Sync.no_sync(),
          latency: 0
        },
        children_log_metadata: options.log_metadata,
        subprocess_supervisor: options.subprocess_supervisor,
        resource_guard: resource_guard
      }
      |> Child.PadSpecHandler.init_pads()

    require CallbackContext.Init

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_init,
        ActionHandler,
        %{context: &CallbackContext.Init.from_state/1},
        [],
        %{state | internal_state: options.user_options}
      )

    {:ok, state, {:continue, :setup}}
  end

  @impl GenServer
  def handle_continue(:setup, state) do
    state = Parent.LifecycleController.handle_setup(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(message, state) do
    do_handle_info(message, state)
  end

  @compile {:inline, do_handle_info: 2}

  defp do_handle_info(Message.new(:handle_unlink, pad_ref), state) do
    state = PadController.handle_unlink(pad_ref, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:parent_notification, notification), state) do
    state = Child.LifecycleController.handle_parent_notification(notification, state)

    {:noreply, state}
  end

  defp do_handle_info(Message.new(:link_request, [pad_ref, direction, link_id, pad_props]), state) do
    state =
      PadController.handle_external_link_request(pad_ref, direction, link_id, pad_props, state)

    {:noreply, state}
  end

  defp do_handle_info(
         Message.new(:stream_management_event, [element_name, pad_ref, event]),
         state
       ) do
    state =
      Parent.LifecycleController.handle_stream_management_event(
        event,
        element_name,
        pad_ref,
        state
      )

    {:noreply, state}
  end

  defp do_handle_info(Message.new(:child_notification, [from, notification]), state) do
    state = Parent.LifecycleController.handle_child_notification(from, notification, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:timer_tick, timer_id), state) do
    state = TimerController.handle_tick(timer_id, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:link_response, [link_id, direction]), state) do
    state = Parent.ChildLifeController.handle_link_response(link_id, direction, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:linking_timeout, pad_ref), state) do
    PadController.handle_linking_timeout(pad_ref, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:child_death, [name, reason]), state) do
    {result, state} = Parent.ChildLifeController.handle_child_death(name, reason, state)

    case result do
      :stop -> {:stop, :normal, state}
      :continue -> {:noreply, state}
    end
  end

  defp do_handle_info(Message.new(:play), state) do
    state = Parent.LifecycleController.handle_playing(state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:initialized, child), state) do
    state = Parent.ChildLifeController.handle_child_initialized(child, state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(:terminate), state) do
    state = Parent.LifecycleController.handle_terminate_request(state)
    {:noreply, state}
  end

  defp do_handle_info(Message.new(_type, _args, _opts) = message, _state) do
    raise Membrane.BinError, "Received invalid message #{inspect(message)}"
  end

  defp do_handle_info({:membrane_clock_ratio, clock, ratio}, state) do
    state = TimerController.handle_clock_update(clock, ratio, state)
    {:noreply, state}
  end

  defp do_handle_info(message, state) do
    state = Parent.LifecycleController.handle_info(message, state)
    {:noreply, state}
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
  def handle_call(Message.new(:get_clock), _from, state) do
    {:reply, state.synchronization.clock, state}
  end
end
