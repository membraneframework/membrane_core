defmodule Membrane.Core.Bin do
  @moduledoc false
  use Bunch
  use GenServer

  import Membrane.Helper.GenServer

  alias __MODULE__.{LinkingBuffer, State}
  alias Membrane.{CallbackError, Core, ComponentPath, Pad, Sync}
  alias Membrane.Core.{CallbackHandler, Message, Telemetry}
  alias Membrane.Core.Child.{PadController, PadSpecHandler}

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

  Bin options are passed to module's `c:handle_init/1` callback.

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
    Message.send(bin, :stop_and_terminate)
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
      |> PadSpecHandler.init_pads()

    with {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_init,
             Membrane.Core.Bin.ActionHandler,
             %{},
             [options.user_options],
             state
           ) do
      {:ok, state}
    else
      {{:error, reason}, _state} ->
        raise CallbackError, kind: :error, callback: {module, :handle_init}, reason: reason

      {other, _state} ->
        raise CallbackError, kind: :bad_return, callback: {module, :handle_init}, value: other
    end
  end

  @impl GenServer
  # Bin-specific message.
  # This forwards all :demand, :caps, :buffer, :event
  # messages to an appropriate element.
  def handle_info(Message.new(type, _args, for_pad: pad) = msg, state)
      when type in [:demand, :caps, :buffer, :event, :push_mode_announcement] do
    outgoing_pad =
      pad
      |> Pad.get_corresponding_bin_pad()

    LinkingBuffer.store_or_send(msg, outgoing_pad, state)
    ~> {:ok, &1}
    |> noreply()
  end

  @impl GenServer
  def handle_info(Message.new(:handle_unlink, pad_ref), state) do
    PadController.handle_pad_removed(pad_ref, state)
    |> noreply()
  end

  @impl GenServer
  def handle_info(message, state) do
    Core.Parent.MessageDispatcher.handle_message(message, state)
  end

  @impl GenServer
  def handle_call(Message.new(:handle_link, [direction, this, other, other_info]), _from, state) do
    PadController.handle_link(direction, this, other, other_info, state) |> reply()
  end

  @impl GenServer
  def handle_call(Message.new(:linking_finished), _from, state) do
    PadController.handle_linking_finished(state)
    |> reply()
  end

  @impl GenServer
  def handle_call(Message.new(:get_clock), _from, state) do
    reply({{:ok, state.synchronization.clock}, state})
  end

  @impl GenServer
  def terminate(reason, state) do
    Telemetry.report_terminate(:bin)

    :ok = state.module.handle_shutdown(reason, state.internal_state)
  end
end
