defmodule Membrane.Bin do
  @callback membrane_bin?() :: true
  # TODO
  @callback handle_init(opts :: any) :: {{:ok, __MODULE__.Spec.t()}, state :: any}

  alias Membrane.Element
  alias Membrane.Core.Element.PadsSpecs
  alias Membrane.Pipeline.Link
  alias Membrane.Bin
  alias Membrane.Bin.{State, Spec, LinkingBuffer}
  alias Membrane.{CallbackError, Core, Element, Notification, BinError}
  alias Element.Pad
  alias Core.{Message, Playback}
  alias Bunch.Type
  alias Membrane.Core.Element.PadController
  alias Membrane.Core.PadSpecHandler
  alias Membrane.Core.ParentUtils
  alias Membrane.Core.ParentState
  alias Membrane.Core.ParentAction

  import Membrane.Helper.GenServer

  require Element
  require Message
  require Pad
  require PadsSpecs

  use Bunch
  use Membrane.Log, tags: :core
  use Membrane.Core.CallbackHandler
  use GenServer
  use Membrane.Core.PlaybackHandler
  use Membrane.Core.PlaybackRequestor

  defmodule Spec do
    @moduledoc """
    This module serves the same purpose as `Membrane.Pipeline.Spec`.

    ## Bin links

    For bins boundries there are special links allowed. User should define links
    between bin's input and first child's input (input-input type) and first
    child's output and bin output (output-output type). In this case, callback module
    creator should name endpoint of the bin with macro `this_bin()`

    Sample definition:

    ```
    %{
    {this_bin(), :input} => {:filter1, :input, buffer: [preferred_size: 10]},
    {:filter1, :output} => {:filter2, :input, buffer: [preferred_size: 10]},
    {:filter2, :output} => {this_bin(), :output, buffer: [preferred_size: 10]}
    }
    ```
    """
    use Membrane.Core.ParentSpec
  end

  @typedoc """
  Defines options that can be passed to `start/3` / `start_link/3` and received
  in `c:handle_init/1` callback.
  """
  @type bin_options_t :: any

  @typedoc """
  Type that defines all valid return values from most callbacks.
  """
  @type callback_return_t ::
          CallbackHandler.callback_return_t(ParentAction.t(), State.internal_state_t())

  @doc """
  Enables to check whether module is membrane bin
  """
  @callback membrane_bin? :: true

  @doc """
  Callback invoked on initialization of bin process. It should parse options
  and initialize element internal state. Internally it is invoked inside
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
              element :: ParentUtils.child_name_t(),
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

  Spec can be started from `c:handle_init/1` callback or as `t:Membrane.Core.ParentAction.spec_action_t/0`
  action.
  """
  @callback handle_spec_started(
              elements :: [ParentUtils.child_name_t()],
              state :: State.internal_state_t()
            ) ::
              callback_return_t

  defguard is_bin_name(term)
           when is_atom(term) or
                  (is_tuple(term) and tuple_size(term) == 2 and is_atom(elem(term, 0)) and
                     is_integer(elem(term, 1)) and elem(term, 1) >= 0)

  defmacro this_bin_marker do
    quote do
      {unquote(__MODULE__), :this_bin}
    end
  end

  # TODO establish options for the private pads
  # * push or pull mode?
  defmacro def_input_pad(name, spec) do
    availability = Keyword.get(spec, :availability, :always)
    input = PadsSpecs.def_pad(name, :input, spec)
    output = PadsSpecs.def_pad({:private, name}, :output, caps: :any, availability: availability)

    quote do
      unquote(input)
      unquote(output)

      if Module.get_attribute(__MODULE__, :bin_pads_pairs) == nil do
        Module.register_attribute(__MODULE__, :bin_pads_pairs, accumulate: true)
        @before_compile {unquote(__MODULE__), :generate_bin_pairs}
      end

      @bin_pads_pairs {unquote(name), {:private, unquote(name)}}
    end
  end

  defmacro def_output_pad(name, spec) do
    availability = Keyword.get(spec, :availability, :always)
    output = PadsSpecs.def_pad(name, :output, spec)

    input =
      PadsSpecs.def_pad({:private, name}, :input,
        caps: :any,
        demand_unit: :buffers,
        availability: availability
      )

    quote do
      unquote(output)
      unquote(input)

      if Module.get_attribute(__MODULE__, :bin_pads_pairs) == nil do
        Module.register_attribute(__MODULE__, :bin_pads_pairs, accumulate: true)
        @before_compile {unquote(__MODULE__), :generate_bin_pairs}
      end

      @bin_pads_pairs {{:private, unquote(name)}, unquote(name)}
    end
  end

  defmacro generate_bin_pairs(env) do
    pad_pairs = Module.get_attribute(env.module, :bin_pads_pairs)

    for {p1, p2} <- pad_pairs do
      quote do
        # TODO do we need both ways?
        def get_corresponding_private_pad({:dynamic, unquote(p1), id}),
          do: {:dynamic, unquote(p2), id}

        def get_corresponding_private_pad({:dynamic, unquote(p2), id}),
          do: {:dynamic, unquote(p1), id}

        def get_corresponding_private_pad(unquote(p1)), do: unquote(p2)
        def get_corresponding_private_pad(unquote(p2)), do: unquote(p1)
      end
    end
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
    with :ok <-
           (if module |> bin? do
              :ok
            else
              :not_bin
            end) do
      apply(GenServer, method, [__MODULE__, {my_name, module, bin_options}, process_options])
    else
      :not_bin ->
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

  @spec handle_spec(Spec.t(), State.t()) :: Type.stateful_try_t([Element.name_t()], State.t())
  defp handle_spec(%Spec{children: children_spec, links: links}, state) do
    debug("""
    Initializing bin spec
    children: #{inspect(children_spec)}
    links: #{inspect(links)}
    """)

    parsed_children = children_spec |> ParentUtils.parse_children()

    {:ok, state} = {parsed_children |> ParentUtils.check_if_children_names_unique(state), state}
    children = parsed_children |> ParentUtils.start_children()
    {:ok, state} = children |> ParentUtils.add_children(state)

    {{:ok, links}, state} = {links |> parse_links, state}
    {links, state} = links |> resolve_links(state)
    {:ok, state} = links |> link_children(state)
    {children_names, children_pids} = children |> Enum.unzip()
    {:ok, state} = {children_pids |> ParentUtils.set_children_watcher(), state}
    {:ok, state} = exec_handle_spec_started(children_names, state)

    children_pids
    |> Enum.each(&change_playback_state(&1, state.playback.state))

    debug("""
    Initialized bin spec
    children: #{inspect(children)}
    children pids: #{inspect(children)}
    links: #{inspect(links)}
    """)

    {{:ok, children_names}, state}
  end

  # Starts children based on given specification and links them to the current
  # process in the supervision tree.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain running.

  @spec parse_links(Spec.links_spec_t() | any) :: Type.try_t([Link.t()])
  defp parse_links(links), do: links |> Bunch.Enum.try_map(&Link.parse/1)

  @spec resolve_links([Link.t()], State.t()) :: [Link.resolved_t()]
  defp resolve_links(links, state) do
    # TODO simplify, don't reduce state seperately
    new_state =
      links
      |> Enum.reduce(state, fn %{from: from, to: to}, s0 ->
        {_, s1} = from |> resolve_link(s0)
        {_, s2} = to |> resolve_link(s1)
        s2
      end)

    links
    |> Enum.map(fn %{from: from, to: to} = link ->
      {from, _} = from |> resolve_link(state)
      {to, _} = to |> resolve_link(state)
      %{link | from: from, to: to}
    end)
    ~> {&1, new_state}
  end

  defp resolve_link(
         %{element: this_bin_marker(), pad_name: pad_name, id: id} = endpoint,
         %{module: bin_mod} = state
       ) do
    # TODO implement unhappy path
    private_bin = bin_mod.get_corresponding_private_pad(pad_name)
    {{:ok, pad_ref}, state} = PadController.get_pad_ref(private_bin, id, state)
    {%{endpoint | pid: self(), pad_ref: pad_ref, pad_name: private_bin}, state}
  end

  defp resolve_link(%{element: element, pad_name: pad_name, id: id} = endpoint, state) do
    with {:ok, pid} <- state |> ParentState.get_child_pid(element),
         {:ok, pad_ref} <- pid |> Message.call(:get_pad_ref, [pad_name, id]) do
      {%{endpoint | pid: pid, pad_ref: pad_ref}, state}
    else
      {:error, {:unknown_child, child}} ->
        raise BinError, "Child #{inspect(child)} does not exist"

      {:error, {:cannot_handle_message, :unknown_pad, _ctx}} ->
        raise BinError, "Child #{inspect(element)} does not have pad #{inspect(pad_name)}"

      {:error, reason} ->
        raise BinError, """
        Error resolving pad #{inspect(pad_name)} of element #{inspect(element)}, \
        reason: #{inspect(reason, pretty: true)}\
        """
    end
  end

  # Links children based on given specification and map for mapping children
  # names into PIDs.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain linked.
  @spec link_children([Link.resolved_t()], State.t()) :: Type.try_t()
  defp link_children(links, state) do
    debug("Linking children: links = #{inspect(links)}")

    with {:ok, state} <- links |> Bunch.Enum.try_reduce_while(state, &link/2),
         :ok <-
           state
           |> ParentState.get_children()
           |> Bunch.Enum.try_each(fn {_pid, pid} -> pid |> Element.handle_linking_finished() end),
         do: {:ok, state}
  end

  defp link(
         %Link{from: %Link.Endpoint{pid: from_pid} = from, to: %Link.Endpoint{pid: to_pid} = to},
         state
       ) do
    from_args = [
      from.pad_ref,
      :output,
      to_pid,
      to.pad_ref,
      nil,
      from.opts
    ]

    {{:ok, pad_from_info}, state} = handle_link(from.pid, from_args, state)

    state =
      if from.pid == self() do
        LinkingBuffer.eval_for_pad(state.linking_buffer, from.pad_ref, state)
        ~> %{state | linking_buffer: &1}
      else
        state
      end

    to_args = [
      to.pad_ref,
      :input,
      from_pid,
      from.pad_ref,
      pad_from_info,
      to.opts
    ]

    {_, state} = handle_link(to.pid, to_args, state)

    state =
      if to.pid == self() do
        LinkingBuffer.eval_for_pad(state.linking_buffer, to.pad_ref, state)
        ~> %{state | linking_buffer: &1}
      else
        state
      end

    {{:ok, :cont}, state}
  end

  defp handle_link(pid, args, state) do
    case self() do
      ^pid ->
        {{:ok, _spec} = res, state} = apply(PadController, :handle_link, args ++ [state])
        {:ok, state} = PadController.handle_linking_finished(state)
        {res, state}

      _ ->
        res = Message.call(pid, :handle_link, args)
        {res, state}
    end
  end

  @spec exec_handle_spec_started([Element.name_t()], State.t()) :: {:ok, State.t()}
  defp exec_handle_spec_started(children_names, state) do
    callback_res =
      CallbackHandler.exec_and_handle_callback(
        :handle_spec_started,
        __MODULE__,
        [children_names],
        state
      )

    with {:ok, _} <- callback_res do
      callback_res
    else
      {{:error, reason}, state} ->
        raise BinError, """
        Callback :handle_spec_started failed with reason: #{inspect(reason)}
        Pipeline state: #{inspect(state, pretty: true)}
        """
    end
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
    with {{:ok, _children}, state} <- spec |> handle_spec(state) do
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

      with {:ok, new_state} <-
             CallbackHandler.exec_and_handle_callback(callback, __MODULE__, [], new_state) do
        PlaybackHandler.continue_playback_change(__MODULE__, new_state)
      else
        error -> error
      end
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
        __MODULE__,
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

  def handle_info(Message.new(:demand_unit, [_demand_unit, _pad_ref]), state) do
    # TODO
    {:ok, state} |> noreply(state)
  end

  def handle_info(Message.new(:continue_initialization), state) do
    %State{children: children, links: links} = state

    {{:ok, links}, state} = {links |> parse_links, state}
    {links, state} = links |> resolve_links(state)
    {:ok, state} = links |> link_children(state)
    {children_names, children_pids} = children |> Enum.unzip()
    {:ok, state} = {children_pids |> ParentUtils.set_children_watcher(), state}
    {:ok, state} = exec_handle_spec_started(children_names, state)

    children_pids
    |> Enum.each(&Element.change_playback_state(&1, state.playback.state))

    debug("""
    Initialized bin spec
    children: #{inspect(children)}
    children pids: #{inspect(children)}
    links: #{inspect(links)}
    """)

    {:ok, state}
    |> noreply()
  end

  def handle_info(Message.new(type, _args, for_pad: pad) = msg, state)
      when type in [:demand, :caps, :buffer, :event] do
    %{module: module, linking_buffer: buf} = state

    outgoing_pad =
      pad
      |> module.get_corresponding_private_pad()

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

  @impl CallbackHandler
  def handle_action({:forward, {elementname, message}}, _cb, _params, state) do
    ParentAction.handle_forward(elementname, message, state)
  end

  def handle_action({:spec, spec = %Spec{}}, _cb, _params, state) do
    with {{:ok, _children}, state} <- handle_spec(spec, state), do: {:ok, state}
  end

  def handle_action({:remove_child, children}, _cb, _params, state) do
    ParentAction.handle_remove_child(children, state)
  end

  def handle_action({:notify, notification}, _cb, _params, state) do
    send_notification(notification, state)
  end

  def handle_action(action, callback, _params, state) do
    ParentAction.handle_unknown_action(action, callback, state.module)
  end

  @spec send_notification(Notification.t(), State.t()) :: {:ok, State.t()}
  defp send_notification(notification, %State{watcher: nil} = state) do
    debug("Dropping notification #{inspect(notification)} as watcher is undefined", state)
    {:ok, state}
  end

  defp send_notification(notification, %State{watcher: watcher, name: name} = state) do
    debug("Sending notification #{inspect(notification)} (watcher: #{inspect(watcher)})", state)
    Message.send(watcher, :notification, [name, notification])
    {:ok, state}
  end

  def set_controlling_pid(server, controlling_pid, timeout \\ 5000) do
    Message.call(server, :set_controlling_pid, controlling_pid, [], timeout)
  end

  defmacro __using__(_) do
    quote location: :keep do
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

      import Membrane.Element.Base, only: [def_options: 1]
      import unquote(__MODULE__), only: [def_input_pad: 2, def_output_pad: 2]

      require Membrane.Core.Element.PadsSpecs

      Membrane.Core.Element.PadsSpecs.ensure_default_membrane_pads()

      @impl true
      def membrane_bin?, do: true

      # TODO think of something better to represent this bin
      defp this_bin, do: unquote(__MODULE__).this_bin_marker()

      @impl true
      def handle_init(_options), do: {{:ok, %Bin.Spec{}}, %{}}

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
