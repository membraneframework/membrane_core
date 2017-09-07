defmodule Membrane.Element do
  @moduledoc """
  Module containing functions spawning, shutting down, inspecting and controlling
  playback of elements.
  """

  use Membrane.Mixins.Log, tags: :core
  use Membrane.Helper
  alias Membrane.Element.Manager.State
  import Membrane.Helper.GenServer
  alias Membrane.Element.Manager.Pad
  use GenServer
  use Membrane.Mixins.Playback

  # Type that defines possible return values of start/start_link functions.
  @type on_start :: GenServer.on_start

  # Type that defines possible process options passed to start/start_link
  # functions.
  @type process_options_t :: GenServer.options

  # Type that defines possible element-specific options passed to
  # start/start_link functions.
  @type element_options_t :: struct | nil

  # Type that defines an element name within a pipeline
  @type name_t :: atom | String.t

  @type pad_name_t :: atom | String.t


  def is_element(module) do
    Code.ensure_loaded?(module) and
    function_exported?(module, :is_membrane_element, 0) and
    module.is_membrane_element
  end


  @doc """
  Starts process for element of given module, initialized with given options and
  links it to the current process in the supervision tree.

  Works similarily to `GenServer.start_link/3` and has the same return values.
  """
  @spec start_link(module, element_options_t, process_options_t) :: on_start
  def start_link(module, name, element_options \\ nil, process_options \\ []), do:
    do_start(:start_link, module, name, element_options, process_options)


  @doc """
  Starts process for element of given module, initialized with given
  elementoptions outside of the supervision tree.

  Works similarily to `GenServer.start/3` and has the same return values.
  """
  @spec start(module, element_options_t, process_options_t) :: on_start
  def start(module, name, element_options \\ nil, process_options \\ []), do:
    do_start(:start, module, name, element_options, process_options)


  defp do_start(method, module, name, element_options, process_options) do
    with :ok <- (if is_element module do :ok else :not_element end)
    do
      debug """
        Element start link: module: #{inspect module},
        element options: #{inspect element_options},
        process options: #{inspect process_options}
        """
      apply GenServer, method, [__MODULE__, {module, name, element_options}, process_options]
    else
      :not_element -> warn_error """
        Cannot start element, passed module #{inspect module} is not a Membrane Element
        """, {:not_element, module}
    end
  end


  @doc """
  Stops given element process.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  Will trigger calling `handle_shutdown/2` element callback.

  Returns `:ok`.
  """
  @spec shutdown(pid, timeout) :: :ok
  def shutdown(server, timeout \\ 5000) do
    debug("Shutdown -> #{inspect(server)}")
    GenServer.stop(server, :normal, timeout)
    :ok
  end


  @doc """
  Sends synchronous call to the given element requesting it to set message bus.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If case of failure, returns `{:error, reason}`
  """
  @spec set_message_bus(pid, pid, timeout) :: :ok | {:error, any}
  def set_message_bus(server, message_bus, timeout \\ 5000) when is_pid(server) do
    GenServer.call(server, {:membrane_set_message_bus, message_bus}, timeout)
  end

  def link(from_pid, to_pid, from_pad, to_pad, params) do
    with \
      :ok <- GenServer.call(from_pid, {:membrane_handle_link, [from_pad, :source, to_pid, to_pad, params]}),
      :ok <- GenServer.call(to_pid, {:membrane_handle_link, [to_pad, :sink, from_pid, from_pad, params]})
    do :ok
    end
  end

  def unlink(server, timeout \\ 5000) do
    server |> GenServer.call(:membrane_unlink, timeout)
  end

  def handle_new_pad(server, direction, pad, timeout \\ 5000) when is_pid server do
    server |> GenServer.call({:membrane_new_pad, [direction, pad]}, timeout)
  end

  def handle_linking_finished(server, timeout \\ 5000) when is_pid server do
    server |> GenServer.call(:membrane_linking_finished, timeout)
  end

  @doc false
  def init({module, name, options}) do
    debug "Element: initializing: #{inspect module}, options: #{inspect options}"
    with {:ok, state} <- module.manager_module.handle_init(module, name, options)
    do
      debug "Element: initialized: #{inspect module}"
      {:ok, state}
    else
      {:error, reason} ->
        warn_error "Failed to initialize element", reason
        {:stop, {:element_init, reason}}
    end
  end


  @doc false
  def terminate(reason, %State{module: module, playback_state: playback_state} = state) do
    case playback_state do
      :stopped ->
        warn_error """
        Terminating: Attempt to terminate element when it is not stopped
        """, reason
      _ -> debug "Terminating element, reason: #{inspect reason}"
    end

    module.manager_module.handle_shutdown(state)
    reason
  end

  defdelegate handle_playback_state(old, new, state), to: Pad

  def handle_call(message, _from, state) do
    message |> Pad.handle_message(:call, state) |> reply(state)
  end

  def handle_info(message, state) do
    message |> Pad.handle_message(:info, state) |> noreply(state)
  end


end
