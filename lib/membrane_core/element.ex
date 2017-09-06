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
  @type elementoptions_t :: struct | nil

  # Type that defines an Element.Manager name within a pipeline
  @type name_t :: atom | String.t

  @type pad_name_t :: atom | String.t



  @doc """
  Starts process for Element.Manager of given module, initialized with given options and
  links it to the current process in the supervision tree.

  Works similarily to `GenServer.start_link/3` and has the same return values.
  """
  @spec start_link(module, elementoptions_t, process_options_t) :: on_start
  def start_link(module, elementoptions \\ nil, process_options \\ []) do
    debug("Start Link: module = #{inspect(module)}, elementoptions = #{inspect(elementoptions)}, process_options = #{inspect(process_options)}")
    GenServer.start_link(__MODULE__, {module, elementoptions}, process_options)
  end


  @doc """
  Starts process for Element.Manager of given module, initialized with given
  elementoptions outside of the supervision tree.

  Works similarily to `GenServer.start/3` and has the same return values.
  """
  @spec start(module, elementoptions_t, process_options_t) :: on_start
  def start(module, elementoptions \\ nil, process_options \\ []) do
    debug("Start: module = #{inspect(module)}, elementoptions = #{inspect(elementoptions)}, process_options = #{inspect(process_options)}")
    GenServer.start(__MODULE__, {module, elementoptions}, process_options)
  end


  @doc """
  Stops given Element.Manager process.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  Will trigger calling `handle_shutdown/2` Element.Manager callback.

  Returns `:ok`.
  """
  @spec shutdown(pid, timeout) :: :ok
  def shutdown(server, timeout \\ 5000) do
    debug("Shutdown -> #{inspect(server)}")
    GenServer.stop(server, :normal, timeout)
    :ok
  end


  @doc """
  Sends synchronous call to the given Element.Manager requesting it to set message bus.

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
  def init({module, options}) do
    debug "element: initializing: #{inspect module}, options: #{inspect options}"
    with {:ok, state} <- module.manager_module.handle_init(module, options)
    do
      debug "element: initialized: #{inspect module}"
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
        Terminating: Attempt to terminate Element.Manager when it is not stopped
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
