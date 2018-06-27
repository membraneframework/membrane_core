defmodule Membrane.Element do
  @moduledoc """
  Module containing functions spawning, shutting down, inspecting and controlling
  playback of elements. These functions are usually called by `Membrane.Pipeline`,
  and can be called from elsewhere only if there is a really good reason for
  doing so.
  """

  alias __MODULE__.Pad
  alias Membrane.Core
  alias Core.Element.{Common, MessageDispatcher, State}
  import Membrane.Helper.GenServer
  use Core.Element.Log, import: false, tags: :core
  use Membrane.Mixins.Log, import: false, tags: :core
  use Membrane.Helper
  use GenServer
  use Membrane.Core.Mixins.Playback

  @typedoc """
  Defines options that can be passed to `start/5` / `start_link/5` and received
  in `c:Membrane.Element.Base.Mixin.CommonBehaviour.handle_init/1` callback.
  """
  @type element_options_t :: struct | nil

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

  @doc """
  Checks whether module is an element.
  """
  def element?(module) do
    module |> Helper.Module.check_behaviour(:membrane_element?)
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
      module |> Module.concat(Options) |> Helper.Module.struct()
    )
  end

  @doc """
  Starts process for element of given module, initialized with given options and
  links it to the current process in the supervision tree.

  Calls `GenServer.start_link/3` underneath.
  """
  @spec start_link(pid, module, name_t, element_options_t, GenServer.options()) ::
          GenServer.on_start()
  def start_link(pipeline, module, name, element_options, process_options \\ []),
    do: do_start(:start_link, pipeline, module, name, element_options, process_options)

  @doc """
  Works similarly to `start_link/3`, but does not link to the current process.
  """
  @spec start(pid, module, name_t) :: GenServer.on_start()
  def start(pipeline, module, name),
    do: start(pipeline, module, name, module |> Module.concat(Options) |> Helper.Module.struct())

  @doc """
  Works similarly to `start_link/5`, but does not link to the current process.
  """
  @spec start(pid, module, name_t, element_options_t, GenServer.options()) :: GenServer.on_start()
  def start(pipeline, module, name, element_options, process_options \\ []),
    do: do_start(:start, pipeline, module, name, element_options, process_options)

  defp do_start(method, pipeline, module, name, element_options, process_options) do
    import Membrane.Mixins.Log

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
      warn_error(
        """
        Cannot start element, passed module #{inspect(module)} is not a Membrane Element.
        Make sure that given module is the right one and it uses Membrane.Element.Base.*
        """,
        {:not_element, module}
      )
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
    import Membrane.Mixins.Log
    debug("Shutdown -> #{inspect(server)}")
    GenServer.stop(server, :normal, timeout)
    :ok
  end

  @doc """
  Sends synchronous call to the given element requesting it to set message bus.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).
  """
  @spec set_message_bus(pid, pid, timeout) :: :ok | {:error, any}
  def set_message_bus(server, message_bus, timeout \\ 5000) when is_pid(server) do
    GenServer.call(server, {:membrane_set_message_bus, message_bus}, timeout)
  end

  @doc """
  Sends synchronous call to the given element requesting it to set controlling pid.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).
  """
  @spec set_controlling_pid(pid, pid, timeout) :: :ok | {:error, any}
  def set_controlling_pid(server, controlling_pid, timeout \\ 5000) when is_pid(server) do
    GenServer.call(server, {:membrane_set_controlling_pid, controlling_pid}, timeout)
  end

  @impl Playback
  def change_playback_state(pid, new_state) do
    send(pid, {:membrane_change_playback_state, new_state})
    :ok
  end

  @doc """
  Sends synchronous calls to two elements, telling them to link with each other.
  """
  @spec link(
          from_element :: pid,
          to_element :: pid,
          from_pad :: Pad.name_t(),
          to_pad :: Pad.name_t(),
          params :: list
        ) :: :ok | {:error, any}
  def link(pid, pid, _, _, _) when is_pid(pid) do
    {:error, :loop}
  end

  def link(from_pid, to_pid, from_pad, to_pad, params) when is_pid(from_pid) and is_pid(to_pid) do
    with :ok <-
           GenServer.call(
             from_pid,
             {:membrane_handle_link, [from_pad, :source, to_pid, to_pad, params]}
           ),
         :ok <-
           GenServer.call(
             to_pid,
             {:membrane_handle_link, [to_pad, :sink, from_pid, from_pad, params]}
           ) do
      :ok
    end
  end

  def link(_, _, _, _, _), do: {:error, :invalid_element}

  @doc """
  Sends synchronous call to element, telling it to unlink all its pads.
  """
  def unlink(server, timeout \\ 5000) do
    server |> GenServer.call(:membrane_unlink, timeout)
  end

  @doc """
  Sends synchronous call to element, requesting it to create a new instance of
  `:on_request` pad.
  """
  def handle_new_pad(server, direction, pad, timeout \\ 5000) when is_pid(server) do
    server |> GenServer.call({:membrane_new_pad, [direction, pad]}, timeout)
  end

  @doc """
  Sends synchronous call to element, informing it that linking has finished.
  """
  def handle_linking_finished(server, timeout \\ 5000) when is_pid(server) do
    server |> GenServer.call(:membrane_linking_finished, timeout)
  end

  @impl GenServer
  def init({pipeline, module, name, options}) do
    import Membrane.Mixins.Log
    Process.monitor(pipeline)
    debug("Element: initializing: #{inspect(module)}, options: #{inspect(options)}")

    with {:ok, state} <- Common.handle_init(module, name, options) do
      debug("Element: initialized: #{inspect(module)}")
      {:ok, state}
    else
      {:error, reason} ->
        warn_error("Failed to initialize element", reason)
        {:stop, {:element_init, reason}}
    end
  end

  @impl GenServer
  def terminate(reason, %State{playback: playback} = state) do
    import Membrane.Mixins.Log

    case playback.state do
      :stopped ->
        debug("Terminating element, reason: #{inspect(reason)}")

      _ ->
        warn_error(
          """
          Terminating: Attempt to terminate element when it is not stopped
          """,
          reason
        )
    end

    Common.handle_shutdown(state)
  end

  @impl Playback
  defdelegate handle_playback_state(old, new, state), to: MessageDispatcher

  @impl Playback
  defdelegate handle_playback_state_changed(old, new, state), to: MessageDispatcher

  @impl Playback
  def playback_warn_error(message, reason, state) do
    import Membrane.Core.Element.Log
    warn_error(message, reason, state)
  end

  @impl GenServer
  def handle_call(message, _from, state) do
    message |> MessageDispatcher.handle_message(:call, state) |> reply(state)
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    import Membrane.Core.Element.Log

    if reason != :normal do
      warn_error(
        "Failing becouse of pipeline failure",
        {:pipeline_failure, reason: reason},
        state
      )
    end

    {:stop, reason, state}
  end

  def handle_info(message, state) do
    message |> MessageDispatcher.handle_message(:info, state) |> noreply(state)
  end
end
