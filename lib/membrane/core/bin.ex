defmodule Membrane.Core.Bin do
  @moduledoc false
  use Bunch
  use GenServer

  alias __MODULE__.State
  alias Membrane.{ComponentPath, Sync}
  alias Membrane.Core.Bin.PadController
  alias Membrane.Core.{CallbackHandler, Child, Message, Parent, Telemetry, TimerController}

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
          log_metadata: Keyword.t()
        }

  @doc """
  Starts the Bin based on given module and links it to the current
  process.

  Bin options are passed to module's `c:Membrane.Bin.handle_init/1` callback.

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

    if Membrane.Bin.bin?(module) do
      Membrane.Logger.debug("""
      Bin #{method}: #{inspect(name)}
      node: #{node},
      module: #{inspect(module)},
      bin options: #{inspect(user_options)}
      """)

      # rpc if necessary
      if node do
        :rpc.call(node, GenServer, method, [Membrane.Core.Bin, options])
      else
        apply(GenServer, method, [Membrane.Core.Bin, options])
      end
    else
      raise """
      Cannot start bin, passed module #{inspect(options.module)} is not a Membrane Bin.
      Make sure that given module is the right one and it uses Membrane.Bin
      """
    end
  end

  @doc """
  Changes bin's playback state to `:stopped` and terminates its process
  """
  @spec stop_and_terminate(bin :: pid) :: :ok
  def stop_and_terminate(bin) do
    Message.send(bin, :terminate)
    :ok
  end

  @impl GenServer
  def init(options) do
    %{parent: parent, name: name, module: module, log_metadata: log_metadata} = options

    Process.monitor(parent)

    name_str = if String.valid?(name), do: name, else: inspect(name)
    :ok = Membrane.Logger.set_prefix(name_str <> " bin")
    :ok = Logger.metadata(log_metadata)
    :ok = ComponentPath.set_and_append(log_metadata[:parent_path] || [], name_str <> " bin")

    Telemetry.report_init(:bin)

    clock_proxy = Membrane.Clock.start_link(proxy: true) ~> ({:ok, pid} -> pid)
    clock = if Bunch.Module.check_behaviour(module, :membrane_clock?), do: clock_proxy, else: nil

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
          stream_sync: Sync.no_sync(),
          latency: 0
        },
        children_log_metadata: log_metadata
      }
      |> Child.PadSpecHandler.init_pads()

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_init,
        Membrane.Core.Bin.ActionHandler,
        %{},
        [options.user_options],
        state
      )

    {:ok, state}
  end

  @impl GenServer
  def handle_info(Message.new(:handle_unlink, pad_ref), state) do
    state = PadController.handle_unlink(pad_ref, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:link_request, [pad_ref, direction, link_id, pad_props]), state) do
    state =
      PadController.handle_external_link_request(pad_ref, direction, link_id, pad_props, state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        Message.new(:playback_state_changed, [pid, new_playback_state]),
        state
      ) do
    state = Parent.ChildLifeController.child_playback_changed(pid, new_playback_state, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:change_playback_state, new_state), state) do
    state = Parent.LifecycleController.change_playback_state(new_state, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:stream_management_event, [element_name, pad_ref, event]), state) do
    state =
      Parent.LifecycleController.handle_stream_management_event(
        event,
        element_name,
        pad_ref,
        state
      )

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:notification, [from, notification]), state) do
    state = Parent.LifecycleController.handle_notification(from, notification, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:timer_tick, timer_id), state) do
    state = TimerController.handle_tick(timer_id, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:link_response, link_id), state) do
    state = Parent.ChildLifeController.LinkHandler.handle_link_response(link_id, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:spec_linking_timeout, spec_ref), state) do
    state = Parent.ChildLifeController.LinkHandler.handle_spec_timeout(spec_ref, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:membrane_clock_ratio, clock, ratio}, state) do
    state = TimerController.handle_clock_update(clock, ratio, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason} = message, state) do
    cond do
      is_child_pid?(pid, state) ->
        state = Parent.ChildLifeController.handle_child_death(pid, reason, state)
        {:noreply, state}

      is_parent_pid?(pid, state) ->
        {:stop, {:shutdown, :parent_crash}, state}

      true ->
        state = Parent.LifecycleController.handle_info(message, state)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(message, state) do
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

  @impl GenServer
  def terminate(reason, state) do
    Telemetry.report_terminate(:bin)
    :ok = state.module.handle_shutdown(reason, state.internal_state)
  end

  defp is_parent_pid?(pid, state) do
    state.parent_pid == pid
  end

  defp is_child_pid?(pid, state) do
    Enum.any?(state.children, fn {_name, entry} -> entry.pid == pid end)
  end
end
