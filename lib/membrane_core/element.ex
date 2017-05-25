defmodule Membrane.Element do
  @moduledoc """
  Module containing functions spawning, shutting down, inspecting and controlling
  playback of elements.
  """

  use Membrane.Mixins.Log
  alias Membrane.Element.State
  alias Membrane.Pad
  alias Membrane.PullBuffer

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

  # Type that defines an potential playback states
  @type playback_state_t :: :stopped | :prepared | :playing




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
  Sends synchronous call to the given element requesting it to get message bus.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `{:ok, pid}`.

  If case of failure, returns `{:error, reason}`
  """
  @spec get_message_bus(pid, timeout) :: :ok | {:error, any}
  def get_message_bus(server, timeout \\ 5000) when is_pid(server) do
    GenServer.call(server, :membrane_get_message_bus, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to clear message bus.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If case of failure, returns `{:error, reason}`
  """
  @spec clear_message_bus(pid, timeout) :: :ok | {:error, any}
  def clear_message_bus(server, timeout \\ 5000) when is_pid(server) do
    GenServer.call(server, :membrane_clear_message_bus, timeout)
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


  @doc """
  Gets PID of source pad of given name.

  In case of success, returns `{:ok, {availability, direction, mode, pid}}`.

  In case of error, returns `{:error, reason}`.
  """
  @spec get_source_pad(pid, Pad.name_t, timeout) ::
    {:ok, {Pad.availability_t, Pad.direction_t, Pad.mode_t, pid}} |
    {:error, any}
  def get_source_pad(server, pad_name, timeout \\ 5000) when is_pid(server) do
    GenServer.call(server, {:membrane_get_pad, :source, pad_name}, timeout)
  end


  @doc """
  Gets PID of sink pad of given name.

  In case of success, returns `{:ok, {availability, direction, mode, pid}}`.

  In case of error, returns `{:error, reason}`.
  """
  @spec get_sink_pad(pid, Pad.name_t, timeout) ::
    {:ok, {Pad.availability_t, Pad.direction_t, Pad.mode_t, pid}} |
    {:error, any}
  def get_sink_pad(server, pad_name, timeout \\ 5000) when is_pid(server) do
    GenServer.call(server, {:membrane_get_pad, :sink, pad_name}, timeout)
  end


  @doc """
  Returns `true` if given module is an element that is a source, `false`
  otherwise.
  """
  @spec is_source_module?(module) :: boolean
  def is_source_module?(module) do
    module.base_module == Membrane.Element.Base.Source
  end


  @doc """
  Returns `true` if given module is an element that is a filter, `false`
  otherwise.
  """
  @spec is_filter_module?(module) :: boolean
  def is_filter_module?(module) do
    module.base_module == Membrane.Element.Base.Filter
  end


  @doc """
  Returns `true` if given module is an element that is a sink, `false`
  otherwise.
  """
  @spec is_sink_module?(module) :: boolean
  def is_sink_module?(module) do
    module.base_module == Membrane.Element.Base.Sink
  end




  # Private API

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
      warn("Terminating: Stacktrace = " <> System.stacktrace() |> Exception.format_stacktrace)
    end

    debug("Terminating: reason = #{inspect(reason)}, state = #{inspect(state)}")
    module.handle_shutdown(internal_state)
  end


  # Callback invoked on incoming play call.
  @doc false
  def handle_call(:membrane_play, _from, %State{playback_state: playback_state} = state) do
    case State.change_playback_state(state, playback_state, :playing, :playing) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, {reason, state}} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Callback invoked on incoming prepare call.
  @doc false
  def handle_call(:membrane_prepare, _from, %State{playback_state: playback_state} = state) do
    case State.change_playback_state(state, playback_state, :prepared, :prepared) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, {reason, state}} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Callback invoked on incoming stop call.
  @doc false
  def handle_call(:membrane_stop, _from, %State{playback_state: playback_state} = state) do
    case State.change_playback_state(state, playback_state, :stopped, :stopped) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, {reason, state}} ->
        {:reply, {:error, reason}, state}
    end
  end


  # Callback invoked on incoming set_message_bus command.
  @doc false
  def handle_call({:membrane_set_message_bus, message_bus}, _from, state) do
    {:reply, :ok, %{state | message_bus: message_bus}}
  end


  # Callback invoked on incoming get_message_bus command.
  @doc false
  def handle_call(:membrane_get_message_bus, _from, %State{message_bus: message_bus} = state) do
    {:reply, {:ok, message_bus}, state}
  end


  # Callback invoked on incoming clear_message_bus command.
  @doc false
  def handle_call(:membrane_clear_message_bus, _from, state) do
    {:reply, :ok, %{state | message_bus: nil}}
  end


  # Callback invoked on incoming get_pad command.
  @doc false
  def handle_call({:membrane_get_pad, pad_direction, pad_name}, _from, state) do
    {:reply, state |> State.get_pad_by_name(pad_direction, pad_name), state}
  end


  # Callback invoked on demand request coming from the source pad in the pull mode
  @doc false
  def handle_info({:membrane_demand, pad_pid, size}, %State{module: module} = state) do
    with {:ok, pad_name} <- State.get_pad_name_by_pid(state, :source, pad_pid),
         {:ok, {actions, state}} <- handle_demand(pad_name, size, state),
         {:ok, state} <- module.base_module.handle_actions(actions, state)
    do
      {:noreply, state}

    else
      {:internal, {:error, {reason, new_internal_state}}} ->
        warn("Failed to handle demand, element callback has returned an error: pad_pid = #{inspect(pad_pid)}, reason = #{inspect(reason)}")
        {:noreply, %{state | internal_state: new_internal_state}}

      {:error, reason} ->
        warn("Failed to handle demand: pad_pid = #{inspect(pad_pid)}, reason = #{inspect(reason)}")
        {:noreply, state}

      other ->
        handle_invalid_callback_return(other)
    end
  end

  # Callback invoked on buffer coming from the sink pad to the sink
  @doc false
  def handle_info({:membrane_buffer, pad_pid, :push, buffer}, %State{module: module, internal_state: internal_state} = state) do
    write_func = cond do
      is_sink_module?(module) -> :handle_write
      is_filter_module?(module) -> :handle_process
    end

    with {:ok, pad_name} <- State.get_pad_name_by_pid(state, :sink, pad_pid),
         {:ok, {actions, new_internal_state}} <- wrap_internal_return(Kernel.apply(module, write_func, [pad_name, buffer, internal_state])),
         {:ok, state} <- module.base_module.handle_actions(actions, %{state | internal_state: new_internal_state})
    do
      {:noreply, state}

    else
      {:internal, {:error, {reason, new_internal_state}}} ->
        warn("Failed to handle write, element callback has returned an error: pad_pid = #{inspect(pad_pid)}, reason = #{inspect(reason)}")
        {:noreply, %{state | internal_state: new_internal_state}}

      {:error, reason} ->
        warn("Failed to handle write: pad_pid = #{inspect(pad_pid)}, reason = #{inspect(reason)}")
        {:noreply, state}

      other ->
        handle_invalid_callback_return(other)
    end
  end

  # Callback invoked on buffer coming from the sink pad to the sink
  @doc false
  def handle_info({:membrane_buffer, pad_pid, :pull, buffer}, %State{module: module, sink_pads_pull_buffers: buffers, source_pads_pull_demands: demands} = state) do
    with \
      {:ok, pad_name} <- State.get_pad_name_by_pid(state, :sink, pad_pid),
      {:ok, pull_buffer} <- State.get_sink_pull_buffer(state, pad_name),
      {:ok, {actions, state}} <- check_and_handle_demands(
          demands |> Enum.to_list,
          %State{state | sink_pads_pull_buffers: %{buffers | pad_name => pull_buffer |> PullBuffer.store(buffer)}}
        ),
      {:ok, state} <- module.base_module.handle_actions(actions, state)
    do
      {:noreply, state}

    else
      {:internal, {:error, {reason, new_internal_state}}} ->
        warn("Failed to handle write, element callback has returned an error: pad_pid = #{inspect(pad_pid)}, reason = #{inspect(reason)}")
        {:noreply, %{state | internal_state: new_internal_state}}

      {:error, reason} ->
        warn("Failed to handle write: pad_pid = #{inspect(pad_pid)}, reason = #{inspect(reason)}")
        {:noreply, state}

      other ->
        handle_invalid_callback_return(other)
    end
  end

  # Callback invoked on other incoming message
  @doc false
  def handle_info(message, %State{module: module, internal_state: internal_state} = state) do
    with {:ok, {actions, new_internal_state}} <- wrap_internal_return(module.handle_other(message, internal_state)),
         {:ok, state} <- module.base_module.handle_actions(actions, %{state | internal_state: new_internal_state})
    do
      {:noreply, state}

    else
      {:internal, {:error, {reason, new_internal_state}}} ->
        warn("Failed to handle other message, element callback has returned an error: message = #{inspect(message)}, reason = #{inspect(reason)}")
        {:noreply, %{state | internal_state: new_internal_state}}

      {:error, reason} ->
        warn("Failed to handle other message: message = #{inspect(message)}, reason = #{inspect(reason)}")
        {:noreply, state}

      other ->
        handle_invalid_callback_return(other)
    end
  end

  defp handle_demand pad_name, size, %State{module: module, internal_state: internal_state} = state do
    with \
      {:ok, {actions, new_internal_state}} <- wrap_internal_return(module.handle_demand(pad_name, size, internal_state))
    do
      {:ok, {actions, %{state | internal_state: new_internal_state}}}
    end
  end

  defp check_and_handle_demands(sources_demands, state, actions \\ [])
  defp check_and_handle_demands([], state, actions), do: {:ok, {actions, state}}
  defp check_and_handle_demands([{src_name, src_demand}|rest], state, actions) do
    with \
      {:ok, {new_actions, state}} <- handle_demand(src_name, src_demand, state)
    do
      check_and_handle_demands rest, state, new_actions ++ actions
    end
  end

  defp handle_invalid_callback_return(return) do
    raise """
    Elements' callback replies are expected to be one of:

        {:ok, {actions, state}}
        {:error, {reason, state}}

    where actions is a list that is specific to base type of the element.

    But got return value of #{inspect(return)} which does not match any of the
    valid return values.

    This is probably a bug in the element, check if its callbacks return values
    in the right format.
    """
  end


  # Helper function that allows to distinguish potentially failed calls in with
  # clauses that operate on internal element state from others that operate on
  # global element state.
  defp wrap_internal_return({:ok, info}), do: {:ok, info}
  defp wrap_internal_return({:error, reason}), do: {:internal, {:error, reason}}
end
