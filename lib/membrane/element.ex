defmodule Membrane.Element do
  @moduledoc """
  Module containing functions spawning, shutting down, inspecting and controlling
  playback of elements.

  These functions are usually called by `Membrane.Pipeline`,
  and can be called from elsewhere only if there is a really good reason for
  doing so.
  """

  alias Membrane.Core
  alias Membrane.Pipeline.Link
  alias Link.Endpoint
  alias Core.Element.{MessageDispatcher, State}
  alias Core.Message
  alias Membrane.ElementLinkError
  import Membrane.Helper.GenServer
  require Message
  use Membrane.Log, tags: :core
  use Bunch
  use GenServer
  use Membrane.Core.PlaybackRequestor

  @typedoc """
  Defines options that can be passed to `start/5` / `start_link/5` and received
  in `c:Membrane.Element.Base.Mixin.CommonBehaviour.handle_init/1` callback.
  """
  @type options_t :: struct | nil

  @typedoc """
  Type that defines an element name by which it is identified.
  """
  @type name_t :: atom | {atom, non_neg_integer}

  @typedoc """
  Defines possible element types:
  - source, producing buffers
  - filter, processing buffers
  - sink, consuming buffers
  """
  @type type_t :: :source | :filter | :sink

  @typedoc """
  Type of user-managed state of element.
  """
  @type state_t :: map | struct

  @doc """
  Checks whether the given term is a valid element name
  """
  defguard is_element_name(term)
           when is_atom(term) or
                  (is_tuple(term) and tuple_size(term) == 2 and is_atom(elem(term, 0)) and
                     is_integer(elem(term, 1)) and elem(term, 1) >= 0)

  @doc """
  Checks whether module is an element.
  """
  def element?(module) do
    module |> Bunch.Module.check_behaviour(:membrane_element?)
  end

  @doc """
  Works similarly to `start_link/5`, but passes element struct (with default values)
  as element options.

  If element does not define struct, `nil` is passed.
  """
  @spec start_link(pid, module, name_t) :: GenServer.on_start()
  def start_link(pipeline, module, name) do
    start_link(
      pipeline,
      module,
      name,
      module |> Module.concat(Options) |> Bunch.Module.struct()
    )
  end

  @doc """
  Starts process for element of given module, initialized with given options and
  links it to the current process in the supervision tree.

  Calls `GenServer.start_link/3` underneath.
  """
  @spec start_link(pid, module, name_t, options_t, GenServer.options()) :: GenServer.on_start()
  def start_link(pipeline, module, name, element_options, process_options \\ []),
    do: do_start(:start_link, pipeline, module, name, element_options, process_options)

  @doc """
  Works similarly to `start_link/3`, but does not link to the current process.
  """
  @spec start(pid, module, name_t) :: GenServer.on_start()
  def start(pipeline, module, name),
    do: start(pipeline, module, name, module |> Module.concat(Options) |> Bunch.Module.struct())

  @doc """
  Works similarly to `start_link/5`, but does not link to the current process.
  """
  @spec start(pid, module, name_t, options_t, GenServer.options()) :: GenServer.on_start()
  def start(pipeline, module, name, element_options, process_options \\ []),
    do: do_start(:start, pipeline, module, name, element_options, process_options)

  defp do_start(method, pipeline, module, name, element_options, process_options) do
    if element?(module) do
      debug("""
      Element start link: module: #{inspect(module)},
      element options: #{inspect(element_options)},
      process options: #{inspect(process_options)}
      """)

      apply(GenServer, method, [
        __MODULE__,
        {pipeline, module, name, element_options},
        process_options
      ])
    else
      raise """
      Cannot start element, passed module #{inspect(module)} is not a Membrane Element.
      Make sure that given module is the right one and it uses Membrane.Element.Base.*
      """
    end
  end

  @doc """
  Stops given element process.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  Will trigger calling `c:Membrane.Element.Base.Mixin.CommonBehaviour.handle_shutdown/1`
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
  Sends synchronous call to the given element requesting it to set watcher.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).
  """
  @spec set_watcher(pid, pid, timeout) :: :ok
  def set_watcher(server, watcher, timeout \\ 5000) when is_pid(server) do
    Message.call(server, :set_watcher, watcher, timeout)
  end

  @doc """
  Sends synchronous call to the given element requesting it to set controlling pid.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).
  """
  @spec set_controlling_pid(pid, pid, timeout) :: :ok | {:error, any}
  def set_controlling_pid(server, controlling_pid, timeout \\ 5000) when is_pid(server) do
    Message.call(server, :set_controlling_pid, controlling_pid, timeout)
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

  @doc """
  Sends synchronous call to element, requesting it to create a new instance of
  `:on_request` pad.
  """
  def handle_new_pad(server, direction, pad, timeout \\ 5000) when is_pid(server) do
    server |> Message.call(:new_pad, [direction, pad], timeout)
  end

  @doc """
  Sends synchronous call to element, informing it that linking has finished.
  """
  def handle_linking_finished(server, timeout \\ 5000) when is_pid(server) do
    server |> Message.call(:linking_finished, [], timeout)
  end

  @impl GenServer
  def init({pipeline, module, name, options}) do
    Process.monitor(pipeline)
    state = State.new(module, name)

    with {:ok, state} <-
           MessageDispatcher.handle_message(
             Message.new(:init, options),
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
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    {:ok, state} =
      MessageDispatcher.handle_message(Message.new(:pipeline_down, reason), :info, state)

    {:stop, reason, state}
  end

  def handle_info(message, state) do
    message |> MessageDispatcher.handle_message(:info, state) |> noreply(state)
  end
end
