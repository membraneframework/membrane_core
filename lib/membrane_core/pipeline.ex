defmodule Membrane.Pipeline do
  @moduledoc """
  Module containing functions for constructing and supervising pipelines.

  Pipelines are units that make it possible to instantiate, link and manage
  elements in convenient way (actually elements should always be used inside
  a pipeline). Linking elements together enables them to pass data to one another,
  and process it in different ways.
  """

  use Membrane.Mixins.Log, tags: :core
  use Membrane.Mixins.CallbackHandler
  use GenServer
  use Membrane.Mixins.Playback
  alias Membrane.Pipeline.{State, Spec}
  alias Membrane.{Element, Message}
  use Membrane.Helper
  import Helper.GenServer
  require Membrane.Element

  @typedoc """
  Defines options that can be passed to `start/3` / `start_link/3` and received
  in `c:handle_init/1` callback.
  """
  @type pipeline_options_t :: any

  @typedoc """
  Action that sends a message to element identified by name.
  """
  @type forward_action_t :: {:forward, {Element.name_t(), Message.t()}}

  @typedoc """
  Action that instantiates elements and links them according to `Membrane.Pipeline.Spec`.

  Elements playback state is changed to the current pipeline state.
  `c:handle_spec_started` callback is executed once it happes.
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
  Callback invoked when pipeline is in `:prepared` state, i.e. all its elements
  are in this state. It receives the previous playback state (`:stopped` or
  `:playing`).
  """
  @callback handle_prepare(
              previous_playback_state :: Playback.state_t(),
              state :: State.internal_state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when pipeline is in `:playing` state, i.e. all its elements
  are in this state.
  """
  @callback handle_play(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when pipeline is in `:playing` state, i.e. all its elements
  are in this state.
  """
  @callback handle_stop(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when message incomes from an element.
  """
  @callback handle_message(
              message :: Message.t(),
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

  @impl Playback
  def change_playback_state(pid, new_state) do
    send(pid, {:membrane_change_playback_state, new_state})
    :ok
  end

  @spec stop_and_terminate(pipeline :: module) :: :ok
  def stop_and_terminate(pipeline) do
    send(pipeline, :membrane_stop_and_terminate)
    :ok
  end

  @impl GenServer
  def init(module) when is_atom(module) do
    init({module, module |> Helper.Module.struct()})
  end

  def init(%module{} = pipeline_options) do
    init({module, pipeline_options})
  end

  def init({module, pipeline_options}) do
    with [init: {{:ok, spec}, internal_state}] <- [init: module.handle_init(pipeline_options)],
         state = %State{internal_state: internal_state, module: module} do
      send(self(), [:membrane_pipeline_spec, spec])
      {:ok, state}
    else
      [init: {:error, reason}] ->
        warn_error(
          """
          Pipeline handle_init callback returned an error
          """,
          reason
        )

        {:stop, {:pipeline_init, reason}}

      [init: other] ->
        reason = {:handle_init_invalid_return, other}

        warn_error(
          """
          Pipeline's handle_init replies are expected to be {:ok, {spec, state}}
          but got #{inspect(other)}.

          This is probably a bug in your pipeline's code, check return value
          of #{module}.handle_init/1.
          """,
          reason
        )

        {:stop, {:pipeline_init, reason}}

      {:error, reason} ->
        warn_error("Error during pipeline initialization", reason)
        {:stop, {:pipeline_init, reason}}
    end
  end

  @doc """
  Checks whether module is a pipeline.
  """
  @spec pipeline?(module) :: boolean
  def pipeline?(module) do
    module |> Helper.Module.check_behaviour(:membrane_pipeline?)
  end

  defp handle_spec(%Spec{children: children, links: links}, state) do
    debug("""
    Initializing pipeline spec
    children: #{inspect(children)}
    links: #{inspect(links)}
    """)

    with {:ok, children} <- children |> parse_children,
         # TODO: add dedup_children veryfying that there are no duplicate children
         {children, state} = children |> resolve_children(state),
         {:ok, {children_to_pids, pids_to_children}} <- children |> start_children,
         state = %State{
           state
           | pids_to_children: Map.merge(state.pids_to_children, pids_to_children),
             children_to_pids: Map.merge(state.children_to_pids, children_to_pids)
         },
         {:ok, links} <- links |> parse_links,
         {{:ok, links}, state} <- links |> resolve_links(state),
         :ok <- links |> link_children(state),
         {children_names, children_pids} = children_to_pids |> Enum.unzip(),
         :ok <- children_pids |> set_children_message_bus,
         {:ok, state} <- exec_and_handle_callback(:handle_spec_started, [children_names], state),
         :ok <-
           children_pids
           |> Helper.Enum.each_with(&Element.change_playback_state(&1, state.playback.state)) do
      debug("""
      Initializied pipeline spec
      children: #{inspect(children)}
      children pids: #{inspect(children_to_pids)}
      links: #{inspect(links)}
      """)

      {{:ok, children_names}, state}
    else
      {:error, reason} ->
        warn_error("Failed to initialize pipeline spec", {:cannot_handle_spec, reason})
    end
  end

  defp parse_children(children) when is_map(children) or is_list(children),
    do: children |> Helper.Enum.map_with(&parse_child/1)

  defp parse_child({name, {%module{} = options, params}})
       when Element.is_element_name(name) and is_list(params) do
    {:ok, %{name: name, module: module, options: options, params: params}}
  end

  defp parse_child({name, {module, params}})
       when Element.is_element_name(name) and is_atom(module) and is_list(params) do
    options = module |> Helper.Module.struct()
    {:ok, %{name: name, module: module, options: options, params: params}}
  end

  defp parse_child({name, module}) do
    parse_child({name, {module, []}})
  end

  defp parse_child(config), do: {:error, invalid_child_config: config}

  defp resolve_children(children, state), do: children |> Enum.map_reduce(state, &resolve_child/2)

  defp resolve_child(%{name: name, params: params} = child, state) do
    if params |> Keyword.get(:indexed) do
      {id, state} = state |> State.get_increase_child_id(name)
      {%{child | name: {name, id}}, state}
    else
      {child, state}
    end
  end

  # Starts children based on given specification and links them to the current
  # process in the supervision tree.
  #
  # On success it returns `{:ok, {names_to_pids, pids_to_names}}` where two
  # values returned are maps that allow to easily map child names to process PIDs
  # in both ways.
  #
  # On error it returns `{:error, reason}`.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain running.
  defp start_children(children) do
    debug("Starting children: #{inspect(children)}")

    with {:ok, result} <- children |> Helper.Enum.map_with(&start_child/1) do
      {names, pids} = result |> Enum.unzip()
      {:ok, {names |> Map.new(), pids |> Map.new()}}
    end
  end

  # Recursion that starts children processes, case when both module and options
  # are provided.
  defp start_child(%{name: name, module: module, options: options}) do
    debug("Pipeline: starting child: name: #{inspect(name)}, module: #{inspect(module)}")

    with {:ok, pid} <- Element.start_link(self(), module, name, options),
         :ok <- Element.set_controlling_pid(pid, self()) do
      {:ok, {{name, pid}, {pid, name}}}
    else
      {:error, reason} ->
        warn_error("Cannot start child #{inspect(name)}", {:cannot_start_child, name, reason})
    end
  end

  defp parse_links(links), do: links |> Helper.Enum.map_with(&parse_link/1)

  defp parse_link(link) do
    with {:ok, link} <-
           link
           ~> (
             {{from, from_pad}, {to, to_pad, params}} ->
               {:ok,
                %{
                  from: %{element: from, pad: from_pad},
                  to: %{element: to, pad: to_pad},
                  params: params
                }}

             {{from, from_pad}, {to, to_pad}} ->
               {:ok,
                %{
                  from: %{element: from, pad: from_pad},
                  to: %{element: to, pad: to_pad},
                  params: []
                }}

             _ ->
               {:error, :invalid_link}
           ),
         :ok <- [link.from.pad, link.to.pad] |> Helper.Enum.each_with(&parse_pad/1) do
      {:ok, link}
    else
      {:error, reason} -> {:error, {:invalid_link, link, reason}}
    end
  end

  defp parse_pad(name)
       when is_atom(name or is_binary(name)) do
    :ok
  end

  defp parse_pad(pad), do: {:error, {:invalid_pad_format, pad}}

  defp resolve_links(links, state) do
    links
    |> Helper.Enum.map_reduce_with(state, fn %{from: from, to: to} = link, st ->
      with {{:ok, from}, st} <- from |> resolve_link(st),
           {{:ok, to}, st} <- to |> resolve_link(st),
           do: {{:ok, %{link | from: from, to: to}}, st}
    end)
  end

  defp resolve_link(%{element: element, pad: pad_name} = elementpad, state) do
    element =
      if state |> State.dynamic?(element) do
        {:ok, last_id} = state |> State.get_last_child_id(element)
        {element, last_id}
      else
        element
      end

    with {:ok, pid} <- state |> State.get_child(element),
         {:ok, pad_name} <- pid |> GenServer.call({:membrane_get_pad_full_name, [pad_name]}) do
      {{:ok, %{element: element, pad: pad_name}}, state}
    else
      {:error, reason} -> {:error, {:resolve_link, elementpad, reason}}
    end
  end

  # Links children based on given specification and map for mapping children
  # names into PIDs.
  #
  # On success it returns `:ok`.
  #
  # On error it returns `{:error, {reason, failed_link}}`.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain linked.
  defp link_children(links, state) do
    debug("Linking children: links = #{inspect(links)}")

    with :ok <- links |> Helper.Enum.each_with(&do_link_children(&1, state)),
         :ok <-
           state.pids_to_children
           |> Helper.Enum.each_with(fn {pid, _} -> pid |> Element.handle_linking_finished() end),
         do: :ok
  end

  defp do_link_children(%{from: from, to: to, params: params} = link, state) do
    with {:ok, from_pid} <- state |> State.get_child(from.element),
         {:ok, to_pid} <- state |> State.get_child(to.element),
         :ok <- Element.link(from_pid, to_pid, from.pad, to.pad, params) do
      :ok
    else
      {:error, reason} -> {:error, {:cannot_link, link, reason}}
    end
  end

  defp set_children_message_bus(elements_pids) do
    with :ok <-
           elements_pids
           |> Helper.Enum.each_with(fn pid ->
             pid |> Element.set_message_bus(self())
           end) do
      :ok
    else
      {:error, reason} -> {:error, {:cannot_set_message_bus, reason}}
    end
  end

  @impl Playback
  def handle_playback_state(_old, new, %State{pids_to_children: pids_to_children} = state) do
    children_pids = pids_to_children |> Map.keys()

    children_pids
    |> Enum.each(fn child ->
      Element.change_playback_state(child, new)
    end)

    state = %{state | pending_pids: children_pids |> MapSet.new()}
    state |> suspend_playback_change
  end

  @impl Playback
  def handle_playback_state_changed(_old, :stopped, %State{terminating?: true} = state) do
    send(self(), :membrane_stop_and_terminate)
    {:ok, state}
  end

  def handle_playback_state_changed(_old, _new, state), do: {:ok, state}

  @impl GenServer
  def handle_info(
        {:membrane_playback_state_changed, _pid, _new_playback_state},
        %State{pending_pids: pending_pids} = state
      )
      when pending_pids == %MapSet{} do
    {:ok, state} |> noreply
  end

  def handle_info(
        {:membrane_playback_state_changed, _pid, new_playback_state},
        %State{playback: %Playback{pending_state: pending_playback_state}} = state
      )
      when new_playback_state != pending_playback_state do
    {:ok, state} |> noreply
  end

  def handle_info(
        {:membrane_playback_state_changed, pid, new_playback_state},
        %State{playback: %Playback{state: current_playback_state}, pending_pids: pending_pids} =
          state
      ) do
    new_pending_pids = pending_pids |> MapSet.delete(pid)
    new_state = %{state | pending_pids: new_pending_pids}

    if new_pending_pids != pending_pids and new_pending_pids |> Enum.empty?() do
      {callback, args} =
        case {current_playback_state, new_playback_state} do
          {_, :prepared} -> {:handle_prepare, [current_playback_state]}
          {:prepared, :playing} -> {:handle_play, []}
          {:prepared, :stopped} -> {:handle_stop, []}
        end

      with {:ok, new_state} <- exec_and_handle_callback(callback, args, new_state) do
        continue_playback_change(new_state)
      else
        error -> error
      end
    else
      {:ok, new_state}
    end
    |> noreply(new_state)
  end

  def handle_info({:membrane_change_playback_state, new_state}, state) do
    resolve_playback_change(new_state, state) |> noreply(state)
  end

  def handle_info(:membrane_stop_and_terminate, state) do
    case state.playback.state do
      :stopped ->
        {:stop, :normal, state}

      _ ->
        state = %{state | terminating?: true}
        lock_playback_state(:stopped, state) |> noreply(state)
    end
  end

  def handle_info([:membrane_pipeline_spec, spec], state) do
    with {{:ok, _children}, state} <- spec |> handle_spec(state) do
      {:ok, state}
    end
    |> noreply(state)
  end

  def handle_info([:membrane_message, from, %Message{} = message], state) do
    with {:ok, _} <- state |> State.get_child(from) do
      exec_and_handle_callback(:handle_message, [message, from], state)
    end
    |> noreply(state)
  end

  def handle_info(message, state) do
    exec_and_handle_callback(:handle_other, [message], state)
    |> noreply(state)
  end

  @impl CallbackHandler
  def handle_action({:forward, {elementname, message}}, _cb, _params, state) do
    with {:ok, pid} <- state |> State.get_child(elementname) do
      send(pid, message)
      {:ok, state}
    else
      {:error, reason} ->
        {:error, {:cannot_forward_message, [element: elementname, message: message], reason}}
    end
  end

  def handle_action({:spec, spec = %Spec{}}, _cb, _params, state) do
    with {{:ok, _children}, state} <- handle_spec(spec, state), do: {:ok, state}
  end

  def handle_action({:remove_child, children}, _cb, _params, state) do
    with {{:ok, pids}, state} <-
           children
           |> Helper.listify()
           |> Helper.Enum.map_reduce_with(state, fn c, st -> State.pop_child(st, c) end),
         :ok <- pids |> Helper.Enum.each_with(&Element.stop/1),
         :ok <- pids |> Helper.Enum.each_with(&Element.unlink/1),
         :ok <- pids |> Helper.Enum.each_with(&Element.shutdown/1) do
      {:ok, state}
    else
      {:error, reason} -> {:error, {:cannot_remove_children, children, reason}}
    end
  end

  def handle_action(action, callback, params, state) do
    warn("""
    Pipelines' #{inspect(state.module)} #{inspect(callback)} returned invalid
    action: #{inspect(action)}. For available actions check
    Membrane.Pipeline.action_t type.
    """)

    super(action, callback, params, state)
  end

  defmacro __using__(_) do
    quote location: :keep do
      alias Membrane.Pipeline
      @behaviour Membrane.Pipeline

      @impl true
      def membrane_pipeline?, do: true

      @impl true
      def handle_init(_options), do: {{:ok, %Spec{}}, %{}}

      @impl true
      def handle_prepare(_playback_state, state), do: {:ok, state}

      @impl true
      def handle_play(state), do: {:ok, state}

      @impl true
      def handle_stop(state), do: {:ok, state}

      @impl true
      def handle_message(_message, _from, state), do: {:ok, state}

      @impl true
      def handle_other(_message, state), do: {:ok, state}

      @impl true
      def handle_spec_started(_new_children, state), do: {:ok, state}

      defoverridable handle_init: 1,
                     handle_prepare: 2,
                     handle_play: 1,
                     handle_stop: 1,
                     handle_message: 3,
                     handle_other: 2,
                     handle_spec_started: 2
    end
  end
end
