defmodule Membrane.Element do
  @moduledoc """
  Module containing functions spawning, shutting down, inspecting and controlling
  playback of elements.
  """

  use Membrane.Mixins.Playback
  use Membrane.Mixins.Log
  alias Membrane.Element.State
  use Membrane.Helper
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




  @doc """
  Starts process for element of given module, initialized with given options and
  links it to the current process in the supervision tree.

  Works similarily to `GenServer.start_link/3` and has the same return values.
  """
  @spec start_link(module, element_options_t, process_options_t) :: on_start
  def start_link(module, element_options \\ nil, process_options \\ []) do
    debug("Start Link: module = #{inspect(module)}, element_options = #{inspect(element_options)}, process_options = #{inspect(process_options)}")
    GenServer.start_link(__MODULE__, {module, element_options}, process_options)
  end


  @doc """
  Starts process for element of given module, initialized with given
  element_options outside of the supervision tree.

  Works similarily to `GenServer.start/3` and has the same return values.
  """
  @spec start(module, element_options_t, process_options_t) :: on_start
  def start(module, element_options \\ nil, process_options \\ []) do
    debug("Start: module = #{inspect(module)}, element_options = #{inspect(element_options)}, process_options = #{inspect(process_options)}")
    GenServer.start(__MODULE__, {module, element_options}, process_options)
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
  Determines module for given process identifier.

  Returns `{:ok, module}` in case of success.

  Returns `{:error, :invalid}` if given pid does not denote element.
  """
  @spec get_module(pid) :: {:ok, module} | {:error, any}
  def get_module(server) when is_pid(server) do
    {:dictionary, items} = :erlang.process_info(server, :dictionary)

    case items |> List.keyfind(:membrane_module, 0) do
      nil ->
        # Seems that given pid is not an element
        {:error, :invalid}

      {:membrane_module, module} ->
        {:ok, module}
    end
  end


  @doc """
  The same as `get_module/1` but throws error in case of failure.
  """
  @spec get_module!(pid) :: module
  def get_module!(server) when is_pid(server) do
    case get_module(server) do
      {:ok, module} ->
        module
      {:error, reason} ->
        throw reason
    end
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


  @doc """
  Sends synchronous call to the given element requesting it to prepare.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is already playing, returns `:ok`.

  If element has failed to reach desired state it returns `{:error, reason}`.
  """
  @spec prepare(pid, timeout) :: :ok | {:error, any}
  def prepare(server, timeout \\ 5000) when is_pid(server) do
    GenServer.call(server, :membrane_prepare, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to start playing.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is already playing, returns `:ok`.

  If element has failed to reach desired state it returns `{:error, reason}`.
  """
  @spec play(pid, timeout) :: :ok | {:error, any}
  def play(server, timeout \\ 5000) when is_pid(server) do
    GenServer.call(server, :membrane_play, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to stop playing.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is not playing, returns `:ok`.

  If element has failed to reach desired state it returns `{:error, reason}`.
  """
  @spec stop(pid, timeout) :: :ok | {:error, any}
  def stop(server, timeout \\ 5000) when is_pid(server) do
    GenServer.call(server, :membrane_stop, timeout)
  end

  def link(from_pid, to_pid, from_pad, to_pad, params) do
    with \
      :ok <- GenServer.call(from_pid, {:membrane_link, from_pad, :source, to_pid, params}),
      :ok <- GenServer.call(to_pid, {:membrane_link, to_pad, :sink, from_pid, params})
    do :ok
    end
  end

  # Private API

  def handle_playback_state(old, new, %State{module: module} = state) do
    debug "Changing playback state of element from #{inspect old} to #{inspect new}"
    with {:ok, state} <- module.base_module.handle_playback_state(old, new, state)
    do
      debug "Changed playback state of element from #{inspect old} to #{inspect new}"
      {:ok, state}
    else
      {:error, reason} -> warn_error """
        Unable to change playback state of element from #{inspect old} to #{inspect new}"
        """, reason
    end

  end

  @doc false
  def init({module, options}) do
    # Call element's initialization callback
    case module.handle_init(options) do
      {:ok, internal_state} ->
        debug("Initialized: internal_state = #{inspect(internal_state)}")

        # Store module name in the process dictionary so it can be used
        # to retreive module from PID in `Membrane.Element.get_module/1`.
        Process.put(:membrane_module, module)

        # Return initial state of the process, including element state.
        state = State.new(module, internal_state)
        {:ok, state}

      {:error, reason} ->
        warn("Failed to initialize element: reason = #{inspect(reason)}")
        {:stop, reason}
    end
  end


  @doc false
  def terminate(reason, %State{module: module, playback_state: playback_state, internal_state: internal_state} = state) do
    if playback_state != :stopped do
      warn("Terminating: Attempt to terminate element when it is not stopped, state = #{inspect(state)}")
      warn("Terminating: Stacktrace = " <> Helper.stacktrace)
    end

    debug("Terminating: reason = #{inspect(reason)}, state = #{inspect(state)}")
    module.handle_shutdown(internal_state)
  end

  # Callback invoked on incoming set_message_bus command.
  @doc false
  def handle_call({:membrane_set_message_bus, message_bus}, _from, state) do
    {:reply, :ok, %{state | message_bus: message_bus}}
  end

  def handle_call({:membrane_link, pad_name, direction, pid, props}, _from, %State{module: module} = state) do
    with {:ok, state} <- module.base_module.handle_link(pad_name, direction, pid, props, state)
    do {:reply, :ok, state}
    else {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # Callback invoked on demand request coming from the source pad in the pull mode
  @doc false
  def handle_info({{:membrane_demand, size}, from}, %State{module: module} = state) do
    {:ok, %{name: pad_name}} = state |> State.get_pad_data(:source, from)
    demand = if size == 0 do "dumb demand" else "demand of size #{inspect size}" end
    debug "Received #{demand} on pad #{inspect pad_name}"
    module.base_module.handle_demand(pad_name, size, state) |> to_noreply_or(state)
  end

  # Callback invoked on buffer coming from the sink pad to the sink
  @doc false
  def handle_info({{:membrane_buffer, buffers}, from}, %State{module: module} = state) do
    {:ok, %{name: pad_name, mode: mode}} = state |> State.get_pad_data(:sink, from)
    debug """
      Received buffers on pad #{inspect pad_name}
      Buffers: #{inspect buffers}
      """
    module.base_module.handle_buffer(mode, pad_name, buffers, state) |> to_noreply_or(state)
  end

  # Callback invoked on incoming caps
  @doc false
  def handle_info({{:membrane_caps, caps}, from}, %State{module: module} = state) do
    {:ok, %{name: pad_name, mode: mode}} = state |> State.get_pad_data(:sink, from)
    debug """
      Received caps on pad #{inspect pad_name}
      Caps: #{inspect caps}
      """
    module.base_module.handle_caps(mode, pad_name, caps, state) |> to_noreply_or(state)
  end

  # Callback invoked on incoming event
  @doc false
  def handle_info({{:membrane_event, event}, from}, %State{module: module} = state) do
    {:ok, %{name: pad_name, mode: mode, direction: direction}} = state
      |> State.get_pad_data(:any, from)
    debug """
      Received event on pad #{inspect pad_name}
      Event: #{inspect event}
      """
    with {:ok, state} <- module.base_module.handle_event(mode, direction, pad_name, event, state)
    do {:noreply, state}
    end
  end

  def handle_info({:membrane_self_demand, pad_name, src_name, size}, %State{module: module} = state) do
    debug "Received self demand for pad #{inspect pad_name} of size #{inspect size}"
    module.base_module.handle_self_demand(pad_name, src_name, size, state) |> to_noreply_or(state)
  end

  # Callback invoked on other incoming message
  @doc false
  def handle_info(message, %State{module: module} = state) do
    debug "Received message: #{inspect message}"
    with {:ok, state} <- module.base_module.handle_message(message, state)
    do {:noreply, state}
    end
  end

  defp to_noreply_or({:ok, new_state}, _), do: {:noreply, new_state}
  defp to_noreply_or(_, state), do: {:noreply, state}

end
