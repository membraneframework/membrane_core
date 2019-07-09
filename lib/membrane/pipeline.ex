defmodule Membrane.Pipeline do
  @moduledoc """
  Module containing functions for constructing and supervising pipelines.

  Pipelines are units that make it possible to instantiate, link and manage
  elements in convenient way (actually elements should always be used inside
  a pipeline). Linking elements together enables them to pass data to one another,
  and process it in different ways.
  """

  alias __MODULE__.{Link, State, Spec}
  alias Membrane.{CallbackError, Clock, Core, Element, Notification, PipelineError, Sync}
  alias Element.Pad
  alias Core.{Message, Playback}
  alias Bunch.Type
  import Membrane.Helper.GenServer
  require Element
  require Message
  require Pad
  use Bunch
  use Membrane.Log, tags: :core
  use Membrane.Core.CallbackHandler
  use GenServer
  use Membrane.Core.PlaybackHandler
  use Membrane.Core.PlaybackRequestor

  @typedoc """
  Defines options that can be passed to `start/3` / `start_link/3` and received
  in `c:handle_init/1` callback.
  """
  @type pipeline_options_t :: any

  @typedoc """
  Action that sends a message to element identified by name.
  """
  @type forward_action_t :: {:forward, {Element.name_t(), Notification.t()}}

  @typedoc """
  Action that instantiates elements and links them according to `Membrane.Pipeline.Spec`.

  Elements playback state is changed to the current pipeline state.
  `c:handle_spec_started` callback is executed once it happens.
  """
  @type spec_action_t :: {:spec, Spec.t()}

  @typedoc """
  Action that stops, unlinks and removes specified child/children from pipeline.
  """
  @type remove_child_action_t :: {:remove_child, Element.name_t() | [Element.name_t()]}

  @typedoc """
  Type describing actions that can be returned from pipeline callbacks.

  Returning actions is a way of pipeline interaction with its elements and
  other parts of framework.
  """
  @type action_t :: forward_action_t | spec_action_t | remove_child_action_t

  @typedoc """
  Type that defines all valid return values from most callbacks.
  """
  @type callback_return_t :: CallbackHandler.callback_return_t(action_t, State.internal_state_t())

  @typep parsed_child_t :: %{name: Element.name_t(), module: module, options: Keyword.t()}

  @doc """
  Enables to check whether module is membrane pipeline
  """
  @callback membrane_pipeline? :: true

  @doc """
  Callback invoked on initialization of pipeline process. It should parse options
  and initialize element internal state. Internally it is invoked inside
  `c:GenServer.init/1` callback.
  """
  @callback handle_init(options :: pipeline_options_t) ::
              {{:ok, Spec.t()}, State.internal_state_t()}
              | {:error, any}

  @doc """
  Callback invoked when pipeline transition from `:stopped` to `:prepared` state has finished,
  that is all of its elements are prepared to enter `:playing` state.
  """
  @callback handle_stopped_to_prepared(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when pipeline transition from `:playing` to `:prepared` state has finished,
  that is all of its elements are prepared to be stopped.
  """
  @callback handle_playing_to_prepared(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when pipeline is in `:playing` state, i.e. all its elements
  are in this state.
  """
  @callback handle_prepared_to_playing(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when pipeline is in `:playing` state, i.e. all its elements
  are in this state.
  """
  @callback handle_prepared_to_stopped(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when a notification comes in from an element.
  """
  @callback handle_notification(
              notification :: Notification.t(),
              element :: Element.name_t(),
              state :: State.internal_state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when pipeline receives a message that is not recognized
  as an internal membrane message.

  Useful for receiving ticks from timer, data sent from NIFs or other stuff.
  """
  @callback handle_other(message :: any, state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when `Membrane.Pipeline.Spec` is linked and in the same playback
  state as pipeline.

  Spec can be started from `c:handle_init/1` callback or as `t:spec_action_t/0`
  action.
  """
  @callback handle_spec_started(elements :: [Element.name_t()], state :: State.internal_state_t()) ::
              callback_return_t

  @doc """
  Starts the Pipeline based on given module and links it to the current
  process.

  Pipeline options are passed to module's `c:handle_init/1` callback.

  Process options are internally passed to `GenServer.start_link/3`.

  Returns the same values as `GenServer.start_link/3`.
  """
  @spec start_link(
          module,
          pipeline_options :: pipeline_options_t,
          process_options :: GenServer.options()
        ) :: GenServer.on_start()
  def start_link(module, pipeline_options \\ nil, process_options \\ []),
    do: do_start(:start_link, module, pipeline_options, process_options)

  @doc """
  Does the same as `start_link/3` but starts process outside of supervision tree.
  """
  @spec start(
          module,
          pipeline_options :: pipeline_options_t,
          process_options :: GenServer.options()
        ) :: GenServer.on_start()
  def start(module, pipeline_options \\ nil, process_options \\ []),
    do: do_start(:start, module, pipeline_options, process_options)

  defp do_start(method, module, pipeline_options, process_options) do
    with :ok <-
           (if module |> pipeline? do
              :ok
            else
              :not_pipeline
            end) do
      debug("""
      Pipeline start link: module: #{inspect(module)},
      pipeline options: #{inspect(pipeline_options)},
      process options: #{inspect(process_options)}
      """)

      apply(GenServer, method, [__MODULE__, {module, pipeline_options}, process_options])
    else
      :not_pipeline ->
        warn_error(
          """
          Cannot start pipeline, passed module #{inspect(module)} is not a Membrane Pipeline.
          Make sure that given module is the right one and it uses Membrane.Pipeline
          """,
          {:not_pipeline, module}
        )
    end
  end

  @doc """
  Changes pipeline's playback state to `:stopped` and terminates its process
  """
  @spec stop_and_terminate(pipeline :: pid) :: :ok
  def stop_and_terminate(pipeline) do
    Message.send(pipeline, :stop_and_terminate)
    :ok
  end

  @impl GenServer
  def init(module) when is_atom(module) do
    init({module, module |> Bunch.Module.struct()})
  end

  def init(%module{} = pipeline_options) do
    init({module, pipeline_options})
  end

  def init({module, pipeline_options}) do
    state = %State{module: module, clock_proxy: Clock.start_link!(proxy: true)}

    with {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_init,
             __MODULE__,
             %{state: false},
             [pipeline_options],
             state
           ) do
      {:ok, state}
    else
      {:error, reason} ->
        raise CallbackError, kind: :error, callback: {module, :handle_init}, reason: reason
    end
  end

  @doc """
  Checks whether module is a pipeline.
  """
  @spec pipeline?(module) :: boolean
  def pipeline?(module) do
    module |> Bunch.Module.check_behaviour(:membrane_pipeline?)
  end

  @spec handle_spec(Spec.t(), State.t()) :: Type.stateful_try_t([Element.name_t()], State.t())
  defp handle_spec(spec, state) do
    %Spec{
      children: children_spec,
      links: links,
      stream_sync: stream_sync,
      clock_provider: clock_provider
    } = spec

    debug("""
    Initializing pipeline spec
    children: #{inspect(children_spec)}
    links: #{inspect(links)}
    """)

    parsed_children = children_spec |> parse_children
    :ok = parsed_children |> check_if_children_names_unique(state)
    children = parsed_children |> start_children(state.clock_proxy)
    state = children |> add_children(state)
    {:ok, state} = choose_clock(children, clock_provider, state)
    {:ok, links} = links |> parse_links
    links = links |> resolve_links(state)
    :ok = links |> link_children(state)
    :ok = set_children_stream_sync(children, links, stream_sync)
    {children_names, children_data} = children |> Enum.unzip()
    :ok = children_data |> set_children_watcher
    {:ok, state} = exec_handle_spec_started(children_names, state)

    children_data
    |> Enum.each(&Element.change_playback_state(&1.pid, state.playback.state))

    debug("""
    Initialized pipeline spec
    children: #{inspect(children)}
    children pids: #{inspect(children)}
    links: #{inspect(links)}
    """)

    {{:ok, children_names}, state}
  end

  @spec parse_children(Spec.children_spec_t() | any) :: [parsed_child_t]
  defp parse_children(children) when is_map(children) or is_list(children),
    do: children |> Enum.map(&parse_child/1)

  defp parse_child({name, %module{} = options})
       when Element.is_element_name(name) do
    %{name: name, module: module, options: options}
  end

  defp parse_child({name, module})
       when Element.is_element_name(name) and is_atom(module) do
    options = module |> Bunch.Module.struct()
    %{name: name, module: module, options: options}
  end

  defp parse_child(config) do
    raise PipelineError, "Invalid children config: #{inspect(config, pretty: true)}"
  end

  @spec check_if_children_names_unique([parsed_child_t], State.t()) :: Type.try_t()
  defp check_if_children_names_unique(children, state) do
    children
    |> Enum.map(& &1.name)
    |> Kernel.++(State.get_children_names(state))
    |> Bunch.Enum.duplicates()
    ~> (
      [] ->
        :ok

      duplicates ->
        raise PipelineError, "Duplicated names in children specification: #{inspect(duplicates)}"
    )
  end

  # Starts children based on given specification and links them to the current
  # process in the supervision tree.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain running.
  # @spec start_children([parsed_child_t]) :: Type.try_t([State.child_t()])
  defp start_children(children, pipeline_clock) do
    debug("Starting children: #{inspect(children)}")

    children |> Enum.map(&start_child(&1, pipeline_clock))
  end

  defp start_child(%{name: name, module: module, options: options}, pipeline_clock) do
    debug("Pipeline: starting child: name: #{inspect(name)}, module: #{inspect(module)}")

    with {:ok, pid} <- Element.start_link(self(), module, name, options, pipeline_clock),
         :ok <- Element.set_controlling_pid(pid, self()),
         {:ok, clock} <- setup_clock(module, pid) do
      {name, %{pid: pid, clock: clock}}
    else
      {:error, reason} ->
        raise PipelineError,
              "Cannot start child #{inspect(name)}, \
              reason: #{inspect(reason, pretty: true)}"
    end
  end

  defp setup_clock(module, pid) do
    if Bunch.Module.loaded_and_function_exported?(module, :clock, 0) do
      clock =
        case module.clock() do
          true -> Clock.start_link!()
          clock -> clock
        end

      with :ok <- Message.call(pid, :clock, clock) do
        {:ok, clock}
      end
    else
      {:ok, nil}
    end
  end

  defp choose_clock(state) do
    choose_clock([], nil, state)
  end

  defp choose_clock(children, provider, state) do
    cond do
      provider -> get_clock_from_provider(children, provider)
      state.clock_provider.clock && state.clock_provider.choice == :manual -> nil
      true -> choose_clock_provider(state.children)
    end
    |> case do
      nil ->
        {:ok, state}

      clock_provider ->
        Message.send(state.clock_proxy, :proxy_to, clock_provider.clock)
        {:ok, %State{state | clock_provider: clock_provider}}
    end
  end

  defp get_clock_from_provider(children, provider) do
    children
    |> Enum.find(fn
      {^provider, _data} -> true
      _ -> false
    end)
    |> case do
      nil ->
        raise PipelineError, "Unknown clock provider: #{inspect(provider)}"

      {^provider, %{clock: nil}} ->
        raise PipelineError, "#{inspect(provider)} is not a clock provider"

      {^provider, %{clock: clock}} ->
        %{clock: clock, provider: provider, choice: :manual}
    end
  end

  defp choose_clock_provider(children) do
    case children |> Bunch.KVList.filter_by_values(& &1.clock) do
      [] ->
        %{clock: nil, provider: nil, choice: :auto}

      [{child, %{clock: clock}}] ->
        %{clock: clock, provider: child, choice: :auto}

      children ->
        raise PipelineError, """
        Cannot choose clock for the pipeline, as multiple elements provide one, namely: #{
          children |> Keyword.keys() |> Enum.join(", ")
        }. Please explicitly select the clock by setting `Spec.clock_provider` parameter.
        """
    end
  end

  @spec add_children([parsed_child_t], State.t()) :: Type.stateful_try_t(State.t())
  defp add_children(children, state) do
    {:ok, state} =
      children
      |> Bunch.Enum.try_reduce(state, fn {name, data}, state ->
        state |> State.add_child(name, data)
      end)

    state
  end

  @spec parse_links(Spec.links_spec_t() | any) :: Type.try_t([Link.t()])
  defp parse_links(links), do: links |> Bunch.Enum.try_map(&Link.parse/1)

  @spec resolve_links([Link.t()], State.t()) :: [Link.resolved_t()]
  defp resolve_links(links, state) do
    links
    |> Enum.map(fn %{from: from, to: to} = link ->
      %{link | from: from |> resolve_link(state), to: to |> resolve_link(state)}
    end)
  end

  defp resolve_link(%{element: element, pad_name: pad_name, id: id} = endpoint, state) do
    with {:ok, %{pid: pid}} <- state |> State.get_child_data(element),
         {:ok, pad_ref} <- pid |> Message.call(:get_pad_ref, [pad_name, id]) do
      %{endpoint | pid: pid, pad_ref: pad_ref}
    else
      {:error, {:unknown_child, child}} ->
        raise PipelineError, "Child #{inspect(child)} does not exist"

      {:error, {:cannot_handle_message, :unknown_pad, _ctx}} ->
        raise PipelineError, "Child #{inspect(element)} does not have pad #{inspect(pad_name)}"

      {:error, reason} ->
        raise PipelineError, """
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

    with :ok <- links |> Bunch.Enum.try_each(&Element.link/1),
         :ok <-
           state
           |> State.get_children()
           |> Bunch.Enum.try_each(fn {_name, %{pid: pid}} ->
             pid |> Element.handle_linking_finished()
           end),
         do: :ok
  end

  @spec set_children_watcher([pid]) :: :ok
  defp set_children_watcher(children_data) do
    :ok = children_data |> Bunch.Enum.try_each(&Element.set_watcher(&1.pid, self()))
  end

  defp set_children_stream_sync(children, links, stream_sync) do
    children = children |> Map.new()

    unless stream_sync do
      [
        children
        |> Map.keys()
        |> Enum.reject(fn cn -> links |> Enum.any?(&(&1.from.element == cn)) end)
      ]
    else
      stream_sync
    end
    |> Enum.each(fn sync_group ->
      {sync, elements} =
        case sync_group do
          {sync, elements} -> {sync, elements}
          elements -> {Sync.start_link!(empty_exit?: true), elements}
        end

      with {elements, []} <- elements |> Enum.map(&children[&1]) |> Enum.split_with(& &1) do
        elements
        |> Enum.each(&Message.call(&1.pid, :set_stream_sync, Sync.register(sync, &1.pid)))
      else
        {_children, unknown} ->
          raise PipelineError,
                "Cannot apply sync - unknown elements: #{unknown |> Enum.join(", ")}"
      end
    end)
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
        raise PipelineError, """
        Callback :handle_spec_started failed with reason: #{inspect(reason)}
        Pipeline state: #{inspect(state, pretty: true)}
        """
    end
  end

  @impl PlaybackHandler
  def handle_playback_state(_old, new, state) do
    children_pids = state |> State.get_children() |> Map.values() |> Enum.map(& &1.pid)

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

  def handle_info(Message.new(:pipeline_spec, spec), state) do
    with {{:ok, _children}, state} <- spec |> handle_spec(state) do
      {:ok, state}
    end
    |> noreply(state)
  end

  def handle_info(Message.new(:notification, [from, notification]), state) do
    with {:ok, _} <- state |> State.get_child_data(from) do
      CallbackHandler.exec_and_handle_callback(
        :handle_notification,
        __MODULE__,
        [notification, from],
        state
      )
    end
    |> noreply(state)
  end

  def handle_info(message, state) do
    CallbackHandler.exec_and_handle_callback(:handle_other, __MODULE__, [message], state)
    |> noreply(state)
  end

  @impl CallbackHandler
  def handle_action(action, callback, params, state) do
    with {:ok, state} <- do_handle_action(action, callback, params, state) do
      {:ok, state}
    else
      {{:error, :invalid_action}, state} ->
        raise CallbackError,
          kind: :invalid_action,
          action: action,
          callback: {state.module, callback}

      error ->
        error
    end
  end

  def do_handle_action({action, _args}, :handle_init, _params, state)
      when action not in [:spec] do
    {{:error, :invalid_action}, state}
  end

  def do_handle_action({:forward, {elementname, message}}, _cb, _params, state) do
    with {:ok, %{pid: pid}} <- state |> State.get_child_data(elementname) do
      send(pid, message)
      {:ok, state}
    else
      {:error, reason} ->
        {{:error, {:cannot_forward_message, [element: elementname, message: message], reason}},
         state}
    end
  end

  def do_handle_action({:spec, spec = %Spec{}}, _cb, _params, state) do
    with {{:ok, _children}, state} <- handle_spec(spec, state), do: {:ok, state}
  end

  def do_handle_action({:remove_child, children}, _cb, _params, state) do
    children = children |> Bunch.listify()

    {:ok, state} =
      if state.clock.provider in children do
        %State{state | clock_provider: %{clock: nil, provider: nil, choice: :auto}}
        |> choose_clock
      else
        {:ok, state}
      end

    withl pop:
            {{:ok, pids}, state} <-
              children |> Bunch.Enum.try_map_reduce(state, fn c, st -> State.pop_child(st, c) end),
          rem: :ok <- pids |> Bunch.Enum.try_each(&Element.stop/1),
          rem: :ok <- pids |> Bunch.Enum.try_each(&Element.unlink/1),
          rem: :ok <- pids |> Bunch.Enum.try_each(&Element.shutdown/1) do
      {:ok, state}
    else
      pop: {{:error, reason}, _state} -> {{:error, reason}, state}
      rem: {:error, reason} -> {{:error, {:cannot_remove_children, children, reason}}, state}
    end
  end

  def do_handle_action(_action, _callback, _params, state) do
    {{:error, :invalid_action}, state}
  end

  defmacro __using__(_) do
    quote location: :keep do
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

      @doc """
      Starts the pipeline `#{inspect(__MODULE__)}` and links it to the current process.

      A proxy for `Membrane.Pipeline.start_link/3`
      """
      @spec start_link(
              pipeline_options :: Pipeline.pipeline_options_t(),
              process_options :: GenServer.options()
            ) :: GenServer.on_start()
      def start_link(pipeline_options \\ nil, process_options \\ []) do
        Pipeline.start_link(__MODULE__, pipeline_options, process_options)
      end

      @doc """
      Starts the pipeline `#{inspect(__MODULE__)}` without linking it
      to the current process.

      A proxy for `Membrane.Pipeline.start/3`
      """
      @spec start(
              pipeline_options :: Pipeline.pipeline_options_t(),
              process_options :: GenServer.options()
            ) :: GenServer.on_start()
      def start(pipeline_options \\ nil, process_options \\ []) do
        Pipeline.start(__MODULE__, pipeline_options, process_options)
      end

      @doc """
      Changes playback state of pipeline to `:playing`

      A proxy for `Membrane.Pipeline.play/1`
      """
      @spec play(pid()) :: :ok
      defdelegate play(pipeline), to: Pipeline

      @doc """
      Changes playback state to `:prepared`.

      A proxy for `Membrane.Pipeline.prepare/1`
      """
      @spec prepare(pid) :: :ok
      defdelegate prepare(pipeline), to: Pipeline

      @doc """
      Changes playback state to `:stopped`.

      A proxy for `Membrane.Pipeline.stop/1`
      """
      @spec stop(pid) :: :ok
      defdelegate stop(pid), to: Pipeline

      @doc """
      Changes pipeline's playback state to `:stopped` and terminates its process.

      A proxy for `Membrane.Pipeline.stop_and_terminate/1`
      """
      @spec stop_and_terminate(pid) :: :ok
      defdelegate stop_and_terminate(pipeline), to: Pipeline

      @impl true
      def membrane_pipeline?, do: true

      @impl true
      def handle_init(_options), do: {:ok, %{}}

      @impl true
      def handle_stopped_to_prepared(state), do: {:ok, state}

      @impl true
      def handle_playing_to_prepared(state), do: {:ok, state}

      @impl true
      def handle_prepared_to_playing(state), do: {:ok, state}

      @impl true
      def handle_prepared_to_stopped(state), do: {:ok, state}

      @impl true
      def handle_notification(_notification, _from, state), do: {:ok, state}

      @impl true
      def handle_other(_message, state), do: {:ok, state}

      @impl true
      def handle_spec_started(_new_children, state), do: {:ok, state}

      defoverridable start: 2,
                     start_link: 2,
                     play: 1,
                     prepare: 1,
                     stop: 1,
                     handle_init: 1,
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
