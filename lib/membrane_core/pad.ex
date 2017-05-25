defmodule Membrane.Pad do
  use GenServer
  use Membrane.Mixins.Log
  alias Membrane.Pad.State

  @type name_t         :: atom | String.t
  @type mode_t         :: :pull | :push
  @type direction_t    :: :source | :sink
  @type availability_t :: :always
  @type known_caps_t   :: :any | [Membrane.Caps.t]
  @type known_pads_t   :: %{required(name_t) => {availability_t, mode_t, known_caps_t}}

  # Type that defines possible return values of start/start_link functions.
  @type on_start :: GenServer.on_start

  # Type that defines possible process options passed to start/start_link
  # functions.
  @type process_options_t :: GenServer.options



  # Private API

  @doc false
  # Starts process for pad of given module, initialized with given options and
  # links it to the current process in the supervision tree.
  #
  # Works similarily to `GenServer.start_link/3` and has the same return values.
  @spec start_link(module, direction_t, process_options_t) :: on_start
  def start_link(module, direction, process_options \\ []) do
    debug("Start Link: module = #{inspect(module)}, direction = #{inspect(direction)}, process_options = #{inspect(process_options)}")
    GenServer.start_link(__MODULE__, {self(), direction, module}, process_options)
  end


  @doc """
  Activates given pad.

  Usually you won't use this manually, as activation is done automatically
  by the framework upon starting playback.
  """
  @spec activate(pid, timeout) :: :ok | {:error, any}
  def activate(server, timeout \\ 5000) when is_pid(server) do
    GenServer.call(server, :membrane_activate, timeout)
  end


  @doc """
  Deactivates given pad.

  Usually you won't use this manually, as deactivation is done automatically
  by the framework upon stopping playback.
  """
  @spec deactivate(pid, timeout) :: :ok | {:error, any}
  def deactivate(server, timeout \\ 5000) when is_pid(server) do
    GenServer.call(server, :membrane_deactivate, timeout)
  end



  @doc false
  # Links given pad with peer.
  @spec link(pid, pid, timeout) :: :ok | {:error, any}
  def link(server, peer, timeout \\ 5000) when is_pid(server) and is_pid(peer) do
    with :ok <- GenServer.call(server, {:membrane_link, peer}, timeout),
         :ok <- GenServer.call(peer, {:membrane_link, server}, timeout)
    do
      :ok
    else
      {:error, reason} ->
        warn("Link failed: server = #{inspect(server)}, peer = #{inspect(peer)}, reason = #{inspect(reason)}")
        {:error, reason}
    end
  end


  # GenServer callbacks

  @doc false
  def init({parent, direction, module}) do
    # Call pad's initialization callback
    case module.handle_init() do
      {:ok, internal_state} ->
        debug("Initialized: internal_state = #{inspect(internal_state)}")

        # Return initial state of the process, including pad state.
        state = State.new(parent, direction, module, internal_state)
        {:ok, state}

      {:error, reason} ->
        warn("Failed to initialize pad: reason = #{inspect(reason)}")
        {:stop, reason}
    end
  end


  @doc false
  def handle_call(:membrane_activate, _from, %State{active: true} = state) do
    warn("Trying to activate pad that is already active, state = #{inspect(state)}")
    {:reply, {:error, :active}, state}
  end

  def handle_call(:membrane_activate, _from, %State{active: false, module: module, peer: peer, direction: direction, internal_state: internal_state} = state) do
    debug("Activating pad, state = #{inspect(state)}")

    # TODO check other return values
    case module.handle_activate(peer, direction, internal_state) do
      {:ok, new_internal_state} ->
        new_state = %{state | internal_state: new_internal_state, active: true}
        debug("Succesfully activated pad, state = #{inspect(new_state)}")
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:membrane_deactivate, _from, %State{active: false} = state) do
    warn("Trying to deactivate pad that is iactive, state = #{inspect(state)}")
    {:reply, {:error, :inactive}, state}
  end

  def handle_call(:membrane_deactivate, _from, %State{active: true, module: module, peer: peer, direction: direction, internal_state: internal_state} = state) do
    debug("Deactivating pad, state = #{inspect(state)}")

    # TODO check other return values
    case module.handle_deactivate(peer, direction, internal_state) do
      {:ok, new_internal_state} ->
        new_state = %{state | internal_state: new_internal_state, active: false}
        debug("Succesfully deactivated pad, state = #{inspect(new_state)}")
        {:reply, :ok, new_state}
    end
  end


  def handle_call({:membrane_link, _peer}, _from, %State{peer: peer} = state)
  when not is_nil(peer) do
    warn("Trying to link pad that is already linked, state = #{inspect(state)}")
    {:reply, {:error, :linked}, state}
  end

  def handle_call({:membrane_link, peer}, _from, %State{peer: nil, direction: direction, module: module, internal_state: internal_state} = state) do
    debug("Linking pad, state = #{inspect(state)}")

    # TODO check other return values
    case module.handle_link(peer, direction, internal_state) do
      {:ok, new_internal_state} ->
        new_state = %{state | internal_state: new_internal_state, peer: peer}
        debug("Succesfully linked pad, state = #{inspect(new_state)}")
        {:reply, :ok, new_state}
    end
  end


  def handle_call(message, from, %State{active: false} = state) do
    warn("Trying to call pad that is not active, message = #{inspect(message)}, from = #{inspect(from)}, state = #{inspect(state)}")
    {:reply, {:error, :inactive}, state}
  end

  def handle_call(message, _from, %State{active: true, parent: parent, direction: direction, module: module, peer: peer, internal_state: internal_state} = state) do
    case module.handle_call(message, parent, peer, direction, internal_state) do
      {:reply, value, new_internal_state} ->
        # TODO check other return values
        {:reply, value, %{state | internal_state: new_internal_state}}
    end
  end


  @doc false
  def handle_info(message, %State{active: false} = state) do
    warn("Dropping other message #{inspect(message)} as pad is not active, state = #{inspect(state)}")
    {:noreply, state}
  end

  def handle_info(message, %State{active: true, parent: parent, direction: direction, module: module, peer: peer, internal_state: internal_state} = state) do
    case module.handle_other(message, parent, peer, direction, internal_state) do
      {:ok, new_internal_state} ->
        # TODO check other return values
        {:noreply, %{state | internal_state: new_internal_state}}

      _ ->
        IO.puts "ATHER"
    end
  end
end
