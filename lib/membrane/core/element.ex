defmodule Membrane.Core.Element do
  @moduledoc false
  # Module containing functions spawning, shutting down, inspecting and controlling
  # playback of elements. These functions are usually called by `Membrane.Pipeline`.
  #
  # Modules in this namespace are responsible for managing elements: handling incoming
  # data, executing callbacks and evaluating actions. These modules can be divided
  # in terms of functionality in the following way:
  # - `Membrane.Core.Element.MessageDispatcher` parses incoming messages and
  #   forwards them to controllers and handlers
  # - Controllers handle messages received from other elements or calls from other
  #   controllers and handlers
  # - Handlers handle actions invoked by element itself
  # - Models contain some utility functions for accessing data in state
  # - `Membrane.Core.Element.State` defines the state struct that these modules
  #   operate on.

  use Membrane.Log, tags: :core
  use Bunch
  use GenServer
  import Membrane.Helper.GenServer
  require Membrane.Core.Message
  alias Membrane.Clock
  alias Membrane.Core.Element.{MessageDispatcher, State}
  alias Membrane.Core.Message
  alias Membrane.Element
  alias Membrane.ElementLinkError
  alias Membrane.Pipeline.{Link, Link.Endpoint}

  @type options_t :: %{
          module: module,
          name: Element.name_t(),
          user_options: Element.options_t(),
          parent: pid,
          clock: Clock.t()
        }

  @doc """
  Starts process for element of given module, initialized with given options and
  links it to the current process in the supervision tree.

  Calls `GenServer.start_link/3` underneath.
  """
  @spec start_link(options_t, GenServer.options()) :: GenServer.on_start()
  def start_link(options, process_options \\ []),
    do: do_start(:start_link, options, process_options)

  @doc """
  Works similarly to `start_link/5`, but does not link to the current process.
  """
  @spec start(options_t, GenServer.options()) :: GenServer.on_start()
  def start(options, process_options \\ []),
    do: do_start(:start, options, process_options)

  defp do_start(method, options, process_options) do
    %{module: module, name: name, user_options: user_options} = options

    if Element.element?(options.module) do
      debug("""
      Element #{method}: #{inspect(name)}
      module: #{inspect(module)},
      element options: #{inspect(user_options)},
      process options: #{inspect(process_options)}
      """)

      apply(GenServer, method, [__MODULE__, options, process_options])
    else
      raise """
      Cannot start element, passed module #{inspect(module)} is not a Membrane Element.
      Make sure that given module is the right one and it uses Membrane.{Source | Filter | Sink}
      """
    end
  end

  @doc """
  Stops given element process.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  Will trigger calling `c:Membrane.Element.Base.handle_shutdown/1`
  callback.
  """
  @spec shutdown(pid, timeout) :: :ok
  def shutdown(server, timeout \\ 5000) do
    import Membrane.Log
    debug("Shutdown -> #{inspect(server)}")
    GenServer.stop(server, :normal, timeout)
    :ok
  end

  @doc """
  Sends synchronous calls to two elements, telling them to link with each other.
  """
  @spec link(link_spec :: %Link{}) :: :ok
  def link(%Link{from: %Endpoint{pid: pid}, to: %Endpoint{pid: pid}}) when is_pid(pid) do
    raise ElementLinkError, "Cannot link element with itself"
  end

  def link(%Link{from: %Endpoint{pid: from_pid} = from, to: %Endpoint{pid: to_pid} = to})
      when is_pid(from_pid) and is_pid(to_pid) do
    with {:ok, pad_from_info} <-
           Message.call(from_pid, :handle_link, [
             from.pad_ref,
             :output,
             to_pid,
             to.pad_ref,
             nil,
             from.opts
           ]),
         {:ok, _pad_to_info} <-
           Message.call(to_pid, :handle_link, [
             to.pad_ref,
             :input,
             from_pid,
             from.pad_ref,
             pad_from_info,
             to.opts
           ]) do
      :ok
    end
  end

  def link(link) do
    raise ElementLinkError, """
    Invalid link - one of pids is invalid.
    #{inspect(link, pretty: true)}
    """
  end

  @impl GenServer
  def init(options) do
    parent_monitor = Process.monitor(options.parent)
    state = options |> Map.put(:parent_monitor, parent_monitor) |> State.new()

    with {:ok, state} <-
           MessageDispatcher.handle_message(
             Message.new(:init, options.user_options),
             :other,
             state
           ) do
      {:ok, state}
    else
      {{:error, reason}, _state} -> {:stop, {:element_init, reason}}
    end
  end

  @impl GenServer
  def terminate(reason, state) do
    {:ok, _state} =
      MessageDispatcher.handle_message(Message.new(:shutdown, reason), :other, state)

    :ok
  end

  @impl GenServer
  def handle_call(message, _from, state) do
    message |> MessageDispatcher.handle_message(:call, state) |> reply(state)
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{parent_monitor: ref} = state) do
    {:ok, state} =
      MessageDispatcher.handle_message(Message.new(:pipeline_down, reason), :info, state)

    {:stop, reason, state}
  end

  @impl GenServer
  def handle_info(message, state) do
    message |> MessageDispatcher.handle_message(:info, state) |> noreply(state)
  end
end
