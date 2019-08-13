defmodule Membrane.Bin do
  use Bunch
  use Membrane.Log, tags: :core
  use GenServer
  use Membrane.Core.PlaybackHandler

  import Membrane.Helper.GenServer

  alias Membrane.{Element, Spec}

  alias Membrane.Core.{
    CallbackHandler,
    PadController,
    PadSpecHandler,
    ChildrenController,
    ParentState,
    ParentAction,
    PadModel,
    PadsSpecs,
    Pad,
    Message,
    Playback
  }

  alias Membrane.Core.Bin.{State, LinkingBuffer, SpecController}
  alias Membrane.{CallbackError, Element, Notification}
  alias Membrane.Core.Bin.ActionHandler

  require Element
  require Message
  require Pad
  require PadsSpecs
  require PadModel

  @typedoc """
  Defines options that can be passed to `start_link/3` and received
  in `c:handle_init/1` callback.
  """
  @type bin_options_t :: any

  @typedoc """
  Type that defines all valid return values from most callbacks.
  """
  @type callback_return_t ::
          CallbackHandler.callback_return_t(ParentAction.t(), State.internal_state_t())

  @doc """
  Enables to check whether module is membrane bin.
  """
  @callback membrane_bin? :: true

  @doc """
  Callback invoked on initialization of bin process. It should parse options
  and initialize bin's internal state. Internally it is invoked inside
  `c:GenServer.init/1` callback.
  """
  @callback handle_init(options :: bin_options_t) ::
              {{:ok, Spec.t()}, State.internal_state_t()}
              | {:error, any}

  @doc """
  Callback invoked when bin transition from `:stopped` to `:prepared` state has finished,
  that is all of its elements are prepared to enter `:playing` state.
  """
  @callback handle_stopped_to_prepared(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when bin transition from `:playing` to `:prepared` state has finished,
  that is all of its elements are prepared to be stopped.
  """
  @callback handle_playing_to_prepared(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when bin is in `:playing` state, i.e. all its elements
  are in this state.
  """
  @callback handle_prepared_to_playing(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when bin is in `:playing` state, i.e. all its elements
  are in this state.
  """
  @callback handle_prepared_to_stopped(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when a notification comes in from an element.
  """
  @callback handle_notification(
              notification :: Notification.t(),
              element :: ChildrenController.child_name_t(),
              state :: State.internal_state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when bin receives a message that is not recognized
  as an internal membrane message.

  Useful for receiving ticks from timer, data sent from NIFs or other stuff.
  """
  @callback handle_other(message :: any, state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when `Membrane.Bin.Spec` is linked and in the same playback
  state as bin.

  Spec can be started from `c:handle_init/1` callback or as
  `t:Membrane.Core.ParentAction.spec_action_t/0` action.
  """
  @callback handle_spec_started(
              elements :: [ChildrenController.child_name_t()],
              state :: State.internal_state_t()
            ) ::
              callback_return_t

  defguard is_bin_name(term)
           when is_atom(term) or
                  (is_tuple(term) and tuple_size(term) == 2 and is_atom(elem(term, 0)) and
                     is_integer(elem(term, 1)) and elem(term, 1) >= 0)

  # TODO maybe move this somewhere to Core.* as this became public?
  @doc """
  This macro defines a struct that represents this bin in callback module.
  """
  defmacro this_bin_marker do
    quote do
      {unquote(__MODULE__), :this_bin}
    end
  end

  @doc PadsSpecs.def_bin_pad_docs(:input)
  defmacro def_input_pad(name, spec) do
    PadsSpecs.def_bin_pad(name, :input, spec)
  end

  @doc PadsSpecs.def_bin_pad_docs(:output)
  defmacro def_output_pad(name, spec) do
    PadsSpecs.def_bin_pad(name, :output, spec)
  end

  @doc """
  Starts the Bin based on given module and links it to the current
  process.

  Bin options are passed to module's `c:handle_init/1` callback.

  Process options are internally passed to `GenServer.start_link/3`.

  Returns the same values as `GenServer.start_link/3`.
  """
  @spec start_link(
          atom,
          module,
          bin_options :: bin_options_t,
          process_options :: GenServer.options()
        ) :: GenServer.on_start()
  def start_link(my_name, module, bin_options \\ nil, process_options \\ []),
    do: do_start(:start_link, my_name, module, bin_options, process_options)

  defp do_start(method, my_name, module, bin_options, process_options) do
    if module |> bin? do
      debug("""
      Bin start link: module: #{inspect(module)},
      bin options: #{inspect(bin_options)},
      process options: #{inspect(process_options)}
      """)

      apply(GenServer, method, [__MODULE__, {my_name, module, bin_options}, process_options])
    else
      warn_error(
        """
        Cannot start bin, passed module #{inspect(module)} is not a Membrane Bin.
        Make sure that given module is the right one and it uses Membrane.Bin
        """,
        {:not_bin, module}
      )

      {:not_bin, module}
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
  def init({my_name, module, bin_options}) do
    with {{:ok, spec}, internal_state} <- module.handle_init(bin_options) do
      state =
        %State{
          internal_state: internal_state,
          bin_options: bin_options,
          module: module,
          name: my_name,
          linking_buffer: LinkingBuffer.new()
        }
        |> PadSpecHandler.init_pads()

      Message.self(:bin_spec, spec)
      {:ok, state}
    else
      {:error, reason} ->
        raise CallbackError, kind: :error, callback: {module, :handle_init}, reason: reason

      other ->
        raise CallbackError, kind: :bad_return, callback: {module, :handle_init}, value: other
    end
  end

  @doc """
  Checks whether module is a bin.
  """
  @spec bin?(module) :: boolean
  def bin?(module) do
    module |> Bunch.Module.check_behaviour(:membrane_bin?)
  end

  @impl PlaybackHandler
  def handle_playback_state(_old, new, state) do
    children_pids = state |> ParentState.get_children() |> Map.values()

    children_pids
    |> Enum.each(fn pid ->
      Element.change_playback_state(pid, new)
    end)

    state = %{state | pending_pids: children_pids |> MapSet.new()}
    PlaybackHandler.suspend_playback_change(state)
  end

  @impl PlaybackHandler
  def handle_playback_state_changed(_old, :stopped, %State{terminating?: true} = state) do
    Message.self(:stop_and_terminate)
    {:ok, state}
  end

  def handle_playback_state_changed(_old, _new, state), do: {:ok, state}

  @impl GenServer
  def handle_info(
        Message.new(:playback_state_changed, [_pid, _new_playback_state]),
        %State{pending_pids: pending_pids} = state
      )
      when pending_pids == %MapSet{} do
    {:ok, state} |> noreply
  end

  def handle_info(Message.new(:bin_spec, spec), state) do
    with {{:ok, _children}, state} <- SpecController |> ChildrenController.handle_spec(spec, state) do
      {:ok, state}
    end
    |> noreply(state)
  end

  def handle_info(
        Message.new(:playback_state_changed, [_pid, new_playback_state]),
        %State{playback: %Playback{pending_state: pending_playback_state}} = state
      )
      when new_playback_state != pending_playback_state do
    {:ok, state} |> noreply
  end

  def handle_info(
        Message.new(:playback_state_changed, [pid, new_playback_state]),
        %State{playback: %Playback{state: current_playback_state}, pending_pids: pending_pids} =
          state
      ) do
    new_pending_pids = pending_pids |> MapSet.delete(pid)
    new_state = %{state | pending_pids: new_pending_pids}

    if new_pending_pids != pending_pids and new_pending_pids |> Enum.empty?() do
      callback = PlaybackHandler.state_change_callback(current_playback_state, new_playback_state)

      CallbackHandler.exec_and_handle_callback(callback, ActionHandler, [], new_state)
      ~>> ({:ok, new_state} -> PlaybackHandler.continue_playback_change(__MODULE__, new_state))
    else
      {:ok, new_state}
    end
    |> noreply(new_state)
  end

  def handle_info(Message.new(:change_playback_state, new_state), state) do
    PlaybackHandler.change_playback_state(new_state, __MODULE__, state) |> noreply(state)
  end

  def handle_info(Message.new(:stop_and_terminate), state) do
    case state.playback.state do
      :stopped ->
        {:stop, :normal, state}

      _ ->
        state = %{state | terminating?: true}

        PlaybackHandler.change_and_lock_playback_state(:stopped, __MODULE__, state)
        |> noreply(state)
    end
  end

  def handle_info(Message.new(:notification, [from, notification]), state) do
    with {:ok, _} <- state |> ParentState.get_child_pid(from) do
      CallbackHandler.exec_and_handle_callback(
        :handle_notification,
        ActionHandler,
        [notification, from],
        state
      )
    end
    |> noreply(state)
  end

  def handle_info(Message.new(:shutdown_ready, child), state) do
    {{:ok, pid}, state} = ParentState.pop_child(state, child)
    {Element.shutdown(pid), state}
  end

  def handle_info(Message.new(:demand_unit, [demand_unit, pad_ref]), state) do
    PadModel.assert_data!(state, pad_ref, %{direction: :output})

    state
    |> PadModel.set_data!(pad_ref, [:other_demand_unit], demand_unit)
    ~> {:ok, &1}
    |> noreply(state)
  end

  def handle_info(Message.new(type, _args, for_pad: pad) = msg, state)
      when type in [:demand, :caps, :buffer, :event] do
    %{linking_buffer: buf} = state

    outgoing_pad =
      pad
      |> Pad.get_corresponding_bin_pad()

    new_buf = LinkingBuffer.store_or_send(buf, msg, outgoing_pad, state)

    {:ok, %{state | linking_buffer: new_buf}} |> noreply()
  end

  def handle_info(message, state) do
    CallbackHandler.exec_and_handle_callback(:handle_other, __MODULE__, [message], state)
    |> noreply(state)
  end

  @impl GenServer
  def handle_call(Message.new(:get_pad_ref, [pad_name, id]), _from, state) do
    PadController.get_pad_ref(pad_name, id, state) |> reply()
  end

  def handle_call(Message.new(:set_controlling_pid, pid), _, state) do
    {:ok, %{state | controlling_pid: pid}}
    |> reply()
  end

  def handle_call(
        Message.new(:handle_link, [pad_ref, pad_direction, pid, other_ref, other_info, props]),
        _from,
        state
      ) do
    {{:ok, info}, state} =
      PadController.handle_link(pad_ref, pad_direction, pid, other_ref, other_info, props, state)

    {:ok, new_state} = PadController.handle_linking_finished(state)

    LinkingBuffer.eval_for_pad(state.linking_buffer, pad_ref, new_state)
    ~> {{:ok, info}, %{new_state | linking_buffer: &1}}
    |> reply()
  end

  def handle_call(Message.new(:linking_finished), _, state) do
    PadController.handle_linking_finished(state)
    |> reply()
  end

  def handle_call(Message.new(:set_watcher, watcher), _, state) do
    {:ok, %{state | watcher: watcher}} |> reply()
  end

  def set_controlling_pid(server, controlling_pid, timeout \\ 5000) do
    Message.call(server, :set_controlling_pid, controlling_pid, [], timeout)
  end

  defmacro __using__(_) do
    marker = this_bin_marker()

    quote location: :keep do
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

      import Membrane.Element.Base, only: [def_options: 1]
      import unquote(__MODULE__), only: [def_input_pad: 2, def_output_pad: 2]

      require Membrane.Core.PadsSpecs

      Membrane.Core.PadsSpecs.ensure_default_membrane_pads()

      @impl true
      def membrane_bin?, do: true

      defp this_bin, do: unquote(marker)

      @impl true
      def handle_init(_options), do: {{:ok, %Membrane.Spec{}}, %{}}

      @impl true
      def handle_stopped_to_prepared(state), do: {:ok, state}

      @impl true
      def handle_playing_to_prepared(state), do: {:ok, state}

      @impl true
      def handle_prepared_to_playing(state), do: {:ok, state}

      @impl true
      def handle_prepared_to_stopped(state), do: {:ok, state}

      @impl true
      def handle_notification(notification, _from, state),
        do: {{:ok, notify: notification}, state}

      @impl true
      def handle_other(_message, state), do: {:ok, state}

      @impl true
      def handle_spec_started(_new_children, state), do: {:ok, state}

      defoverridable handle_init: 1,
                     handle_stopped_to_prepared: 1,
                     handle_playing_to_prepared: 1,
                     handle_prepared_to_playing: 1,
                     handle_prepared_to_stopped: 1,
                     handle_notification: 3,
                     handle_other: 2,
                     handle_spec_started: 2
    end
  end
end
