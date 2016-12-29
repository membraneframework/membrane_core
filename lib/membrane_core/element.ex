defmodule Membrane.Element do
  @moduledoc """
  Module containing functions spawning, shutting down, inspecting and controlling
  playback of elements.
  """

  use Membrane.Mixins.Log


  # Type that defines what may be sent from one element to another.
  @type sendable_t :: %Membrane.Buffer{} | %Membrane.Event{}

  # Type that defines a single command that may be returned from handle_*
  # callbacks.
  #
  # If it is `{:send, pad_name, [buffers_or_events]}` it will cause sending
  # given buffers and/or events downstream to the linked elements via pad of
  # given name.
  @type callback_return_command_t ::
    {:send, Membrane.Pad.name_t, [sendable_t]}

  # Type that defines list of commands that may be returned from handle_*
  # callbacks.
  @type callback_return_commands_t :: [] | [callback_return_command_t]



  @doc """
  Starts process for element of given module, initialized with given options and
  links it to the current process in the supervision tree.

  Works similarily to `GenServer.start_link/3` and has the same return values.
  """
  @spec start_link(module, struct, GenServer.options) :: GenServer.on_start
  def start_link(module, element_options, process_options \\ []) do
    debug("Start Link: module = #{inspect(module)}, element_options = #{inspect(element_options)}, process_options = #{inspect(process_options)}")
    GenServer.start_link(__MODULE__, {module, element_options}, process_options)
  end


  @doc """
  Starts process for element of given module, initialized with given
  element_options outside of the supervision tree.

  Works similarily to `GenServer.start/3` and has the same return values.
  """
  @spec start(module, struct, GenServer.options) :: GenServer.on_start
  def start(module, element_options, process_options \\ []) do
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

    case items |> List.keyfind(:membrane_element_module, 0) do
      nil ->
        # Seems that given pid is not an element
        {:error, :invalid}

      {_key, module} ->
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
  Returns `true` if given module can act as a source element, `false` otherwise.
  """
  @spec is_source?(module) :: boolean
  def is_source?(module) do
    # FIXME use module attributes instead of checking if function is defined
    module.__info__(:functions)
      |> List.keyfind(:known_source_pads, 0) != nil
  end


  @doc """
  Returns `true` if given module can act as a sink element, `false` otherwise.
  """
  @spec is_sink?(module) :: boolean
  def is_sink?(module) do
    # FIXME use module attributes instead of checking if function is defined
    module.__info__(:functions)
      |> List.keyfind(:known_sink_pads, 0) != nil
  end


  @doc """
  Sends synchronous call to the given element requesting it to prepare.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is already playing, returns `:noop`.

  If element has failed to reach desired state it returns `{:error, reason}`.
  """
  @spec prepare(pid, timeout) :: :ok | :noop | {:error, any}
  def prepare(server, timeout \\ 5000) when is_pid(server) do
    debug("Prepare -> #{inspect(server)}")
    GenServer.call(server, :membrane_prepare, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to start playing.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is already playing, returns `:noop`.

  If element has failed to reach desired state it returns `{:error, reason}`.
  """
  @spec play(pid, timeout) :: :ok | :noop | {:error, any}
  def play(server, timeout \\ 5000) when is_pid(server) do
    debug("Play -> #{inspect(server)}")
    GenServer.call(server, :membrane_play, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to stop playing.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is not playing, returns `:noop`.

  If element has failed to reach desired state it returns `{:error, reason}`.
  """
  @spec stop(pid, timeout) :: :ok | :noop | {:error, any}
  def stop(server, timeout \\ 5000) when is_pid(server) do
    debug("Stop -> #{inspect(server)}")
    GenServer.call(server, :membrane_stop, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to add given
  element to the list of destinations for buffers that are sent from the
  element.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If destination is already present, returns `:noop`.

  In case of any of server and destination are the same element,
  returns `{:error, :loop}`.

  In case of any of server or destination is not a pid of an element,
  returns `{:error, :invalid_element}`.

  In case of server is not a source element, returns
  `{:error, :invalid_direction}`.

  In case of destination is not a sink element, returns
  `{:error, {:invalid_direction, pid}}`.
  """
  @spec link({pid, Membrane.Pad.name_t}, {pid, Membrane.Pad.name_t}, timeout) ::
    :ok |
    :noop |
    {:error, :invalid_element} |
    {:error, :invalid_direction} |
    {:error, :loop}
  def link(server, destination, timeout \\ 5000)


  def link({server, server_pad}, {destination, destination_pad}, _timeout)
  when is_pid(server) and is_pid(destination) and server == destination do
    warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: Link source and target are the same")
    {:error, :loop}
  end


  def link({server, server_pad}, {destination, destination_pad}, timeout)
  when is_pid(server) and is_pid(destination) do
    debug("Linking #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}")

    case get_module(server) do
      {:ok, server_module} ->
        case get_module(destination) do
          {:ok, destination_module} ->
            cond do
              is_source?(server_module) && is_sink?(destination_module) ->
                # TODO check if pads are present
                # TODO check if pads match at all
                # TODO check if pads are not already linked
                # FIXME send membrane_link with particular pad combination
                GenServer.call(server, {:membrane_link, destination}, timeout)

              !is_source?(server_module) ->
                warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: #{inspect(server)} (#{server_module}) is not a source element")
                {:error, :invalid_direction}

              !is_sink?(destination_module) ->
                warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: #{inspect(destination)} (#{destination_module}) is not a sink element")
                {:error, :invalid_direction}
            end

          {:error, :invalid} ->
            warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: #{inspect(destination)} is not a PID of an element")
            {:error, :invalid_element}
        end

      {:error, :invalid} ->
        warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: #{inspect(server)} is not a PID of an element")
        {:error, :invalid_element}
    end
  end



  # Private API

  @doc false
  def init({module, options}) do
    # Call element's initialization callback
    case module.handle_init(options) do
      {:ok, element_state} ->
        debug("Initialized: element_state = #{inspect(element_state)}")

        # Store module name in the process dictionary so it can be used
        # to retreive module from PID in `Membrane.Element.get_module/1`.
        Process.put(:membrane_element_module, module)

        # Determine initial list of source pads
        source_pads = if is_source?(module) do
          module.known_source_pads() |> known_pads_to_pads_state
        else
          nil
        end

        # Determine initial list of sink pads
        sink_pads = if is_sink?(module) do
          module.known_sink_pads() |> known_pads_to_pads_state
        else
          nil
        end

        # Return initial state of the process, including element state.
        {:ok, %{
          module: module,
          playback_state: :stopped,
          source_pads: source_pads,
          sink_pads: sink_pads,
          element_state: element_state,
        }}

      {:error, reason} ->
        warn("Failed to initialize element: reason = #{inspect(reason)}")
        {:stop, reason}
    end
  end


  @doc false
  def terminate(reason, %{module: module, playback_state: playback_state, element_state: element_state} = state) do
    if playback_state != :stopped do
      warn("Terminating: Attempt to terminate element when it is not stopped, state = #{inspect(state)}")
    end

    debug("Terminating: reason = #{inspect(reason)}, state = #{inspect(state)}")
    module.handle_shutdown(element_state)
  end


  # Callback invoked on incoming prepare command.
  @doc false
  def handle_call(:membrane_prepare, _from, %{module: module, playback_state: playback_state, element_state: element_state} = state) do
    case playback_state do
      :stopped ->
        case module.handle_prepare(element_state) do
          {:ok, new_element_state} ->
            debug("Handle Prepare: OK, new state = #{inspect(new_element_state)}")
            {:reply, :ok, %{state | playback_state: :prepared, element_state: new_element_state}}

          {:error, reason} ->
            warn("Handle Prepare: Error, reason = #{inspect(reason)}")
            {:reply, {:error, reason}, state} # FIXME handle errors
        end

      :prepared ->
        warn("Handle Prepare: Error, already prepared")
        # Do nothing if already prepared
        {:reply, :noop, state}

      :playing ->
        warn("Handle Prepare: Error, already playing")
        # Do nothing if already playing
        {:reply, :noop, state}
    end
  end


  # Callback invoked on incoming play command.
  @doc false
  def handle_call(:membrane_play, from, %{module: module, playback_state: playback_state, element_state: element_state} = state) do
    case playback_state do
      :stopped ->
        case module.handle_prepare(element_state) do
          {:ok, new_element_state} ->
            debug("Handle Play: Prepared, new state = #{inspect(new_element_state)}")
            handle_call(:membrane_play, from, %{state | playback_state: :prepared, element_state: new_element_state})

          {:error, reason} ->
            warn("Handle Play: Error while preparing, reason = #{inspect(reason)}")
            {:reply, {:error, reason}, state} # FIXME handle errors
        end

      :prepared ->
        case module.handle_play(element_state) do
          {:ok, new_element_state} ->
            debug("Handle Play: OK, new state = #{inspect(new_element_state)}")
            {:reply, :ok, %{state | playback_state: :playing, element_state: new_element_state}}

          {:error, reason} ->
            warn("Handle Play: Error, reason = #{inspect(reason)}")
            {:reply, {:error, reason}, state} # FIXME handle errors
        end

      :playing ->
        warn("Handle Play: Error, already playing")
        # Do nothing if already playing
        {:reply, :noop, state}
    end
  end


  # Callback invoked on incoming stop command.
  @doc false
  def handle_call(:membrane_stop, _from, %{module: module, playback_state: playback_state, element_state: element_state} = state) do
    case playback_state do
      :stopped ->
        warn("Handle Stop: Error, already stopped")
        # Do nothing if already stopped
        {:reply, :noop, state}

      :prepared ->
        case module.handle_stop(element_state) do
          {:ok, new_element_state} ->
            debug("Handle Stop: OK, new state = #{inspect(new_element_state)}")
            {:reply, :ok, %{state | playback_state: :stopped, element_state: new_element_state}}

          {:error, reason} ->
            warn("Handle Stop: Error, reason = #{inspect(reason)}")
            {:reply, {:error, reason}, state} # FIXME handle errors
        end

      :playing ->
        case module.handle_stop(element_state) do
          {:ok, new_element_state} ->
            debug("Handle Stop: OK, new state = #{inspect(new_element_state)}")
            {:reply, :ok, %{state | playback_state: :stopped, element_state: new_element_state}}

          {:error, reason} ->
            warn("Handle Stop: Error, reason = #{inspect(reason)}")
            {:reply, {:error, reason}, state} # FIXME handle errors
        end
    end
  end


  # Callback invoked on incoming link request.
  @doc false
  def handle_call({:membrane_link, destination}, _from, state) do
    {:reply, :ok, state} # TODO
  end


  # Callback invoked on incoming buffer.
  #
  # If element is playing it will delegate actual processing to handle_buffer/3.
  #
  # Otherwise it will silently drop the buffer.
  @doc false
  def handle_info({:membrane_buffer, buffer}, %{module: module, element_state: element_state, playback_state: playback_state} = state) do
    if is_sink?(module) do
      case playback_state do
        :stopped ->
          warn("Incoming buffer: Error, not started (buffer = #{inspect(buffer)})")
          {:noreply, state}

        :prepared ->
          warn("Incoming buffer: Error, not started (buffer = #{inspect(buffer)})")
          {:noreply, state}

        :playing ->
          module.handle_buffer(buffer, element_state) |> handle_callback(state)
      end

    else
      throw :buffer_on_non_sink
    end
  end


  # Callback invoked on other incoming message
  @doc false
  def handle_info(message, %{module: module, element_state: element_state} = state) do
    module.handle_other(message, element_state) |> handle_callback(state)
  end


  # Converts list of known pads into map of pad states
  defp known_pads_to_pads_state(known_pads) do
    known_pads
    |> Map.to_list
    |> Enum.filter(fn({_name, {availability, _caps}}) ->
      availability == :always
    end)
    |> Enum.reduce(%{}, fn({name, {_availability, _caps}}, acc) ->
      acc |> Map.put(name, %{peer: nil, caps: nil})
    end)
  end


  # Generic handler that can be used to convert return value from
  # element callback to reply that is accepted by GenServer.handle_info.
  #
  # Case when callback returned success and requests no further action.
  defp handle_callback({:ok, new_element_state}, state) do
    debug("Handle callback: OK")
    {:noreply, %{state | element_state: new_element_state}}
  end


  # Generic handler that can be used to convert return value from
  # element callback to reply that is accepted by GenServer.handle_info.
  #
  # Case when callback returned success and wants to send some messages
  # (such as buffers) in response.
  defp handle_callback({:ok, commands, new_element_state}, state) do
    debug("Handle callback: OK + commands #{inspect(commands)}")
    :ok = handle_commands(commands, state)
    {:noreply, %{state | element_state: new_element_state}}
  end


  # Generic handler that can be used to convert return value from
  # element callback to reply that is accepted by GenServer.handle_info.
  #
  # Case when callback returned failure.
  defp handle_callback({:error, reason, new_element_state}, state) do
    warn("Handle callback: Error (reason = #{inspect(reason)}")
    {:noreply, %{state | element_state: new_element_state}}
    # TODO handle errors
  end


  defp handle_commands([], state) do
    {:ok, state}
  end


  # Handles command that is supposed to send buffer of event from the
  # given pad to its linked peer.
  defp handle_commands([{:send, {pad, buffer_or_event}}|tail], state) do
    debug("Sending message from pad #{inspect(pad)}: #{inspect(buffer_or_event)}")
    # :ok = send_message(head, link_destinations)

    handle_commands(tail, state)
  end


  # Handles command that is informs that caps on given pad were set.
  #
  # If this pad has a peer it will additionally send Membrane.Event.caps
  # to it.
  defp handle_commands([{:caps, {pad, caps}}|tail], state) do
    debug("Setting caps for pad #{inspect(pad)} to #{inspect(caps)}")
    # :ok = send_message(head, link_destinations)

    handle_commands(tail, state)
  end
end
