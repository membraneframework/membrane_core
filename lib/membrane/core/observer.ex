defmodule Membrane.Core.Observer do
  @moduledoc false

  use GenServer
  alias Membrane.{ComponentPath, Pad}

  @unsafely_name_processes_for_observer Application.compile_env(
                                          :membrane_core,
                                          :unsafely_name_processes_for_observer,
                                          []
                                        )
  @metrics_enabled Application.compile_env(:membrane_core, :enable_metrics, true)

  @type component_config :: %{
          optional(:parent_path) => ComponentPath.path(),
          optional(:log_metadata) => Logger.metadata(),
          name: Membrane.Child.name(),
          component_type: :element | :bin | :pipeline,
          pid: pid()
        }

  @type link_observability_data :: %{
          optional(:path) => ComponentPath.path(),
          optional(:observer_dbg_process) => pid | nil
        }

  @type graph_update ::
          {:graph,
           [
             %{entity: :component, path: ComponentPath.path(), pid: pid}
             | %{
                 entity: :link,
                 from: ComponentPath.path(),
                 to: ComponentPath.path(),
                 output: Pad.ref(),
                 input: Pad.ref()
               }
           ], :add | :remove}

  @type metrics_update ::
          {:metrics, [{{metric :: atom, ComponentPath.path(), Pad.ref()}, value :: integer()}],
           timestamp_ms :: integer()}

  @type t :: %__MODULE__{pid: pid(), ets: :ets.tid() | nil}

  @enforce_keys [:pid, :ets]
  defstruct @enforce_keys

  @scrape_interval 1000

  @doc false
  @spec start_link(%{ets: :ets.tid()}) :: {:ok, pid()}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Creates a new observer and configures observability for the pipeline.

  Must be called by the pipeline process.
  """
  @spec new(component_config(), pid()) :: t()
  def new(config, supervisor) do
    ets = create_ets()

    {:ok, pid} =
      Membrane.Core.SubprocessSupervisor.start_link_utility(supervisor, {__MODULE__, %{ets: ets}})

    observer = %__MODULE__{pid: pid, ets: ets}
    setup_process_local_observability(config, %{observer: observer})
    observer
  end

  if @metrics_enabled do
    defp create_ets(), do: :ets.new(__MODULE__, [:public, write_concurrency: true])
  else
    defp create_ets(), do: nil
  end

  @doc """
  Registers a component in the observer and configures the component's observability.

  Must be called by an element's or bin's process.
  """
  @spec register_component(t(), component_config()) :: :ok
  def register_component(observer, config) do
    setup_process_local_observability(config, %{observer: observer})

    send(
      observer.pid,
      {:graph,
       %{
         entity: :component,
         pid: self(),
         type: config.component_type,
         path: Membrane.ComponentPath.get()
       }}
    )

    :ok
  end

  @doc """
  Configures observability for a component's utility process.
  """
  @spec setup_component_utility(component_config(), String.t()) :: :ok
  def setup_component_utility(config, utility_name) do
    setup_process_local_observability(config, %{utility_name: utility_name})
  end

  # Sets component path, logger metadata and adds necessary entries to the process dictionary
  # Also registers the process with a meaningful name for easier introspection with
  # observer if enabled by setting `unsafely_name_processes_for_observer: :components`
  # in config.exs.
  defp setup_process_local_observability(config, opts) do
    utility_name = Map.get(opts, :utility_name)
    observer = Map.get(opts, :observer)
    %{name: name, component_type: component_type, pid: pid} = config

    # Metrics are currently reported only if the component
    # is on the same node as the pipeline
    if observer && node(observer.pid) == node(),
      do: Process.put(:__membrane_observer_ets__, observer.ets)

    if component_type == :pipeline and !utility_name,
      do: Process.put(:__membrane_pipeline__, true)

    utility_name = if utility_name == "", do: "", else: " #{utility_name}"
    parent_path = Map.get(config, :parent_path, [])
    log_metadata = Map.get(config, :log_metadata, [])
    Logger.metadata(log_metadata)
    pid_string = pid |> :erlang.pid_to_list() |> to_string()

    {name, unique_prefix, component_type_suffix} =
      if name,
        do: {name, pid_string <> " ", ""},
        else: {pid_string, "", " (#{component_type})"}

    name_suffix = if component_type == :element, do: "", else: "/"
    name_str = if(String.valid?(name), do: name, else: inspect(name)) <> name_suffix

    register_name_for_observer(
      :"##{unique_prefix}#{name_str}#{component_type_suffix}#{utility_name}"
    )

    component_path = parent_path ++ [name_str]
    ComponentPath.set(component_path)

    Membrane.Logger.set_prefix(ComponentPath.format(component_path) <> utility_name)

    :ok
  end

  if :components in @unsafely_name_processes_for_observer do
    defp register_name_for_observer(name) do
      if Process.info(self(), :registered_name) == {:registered_name, []} do
        Process.register(self(), name)
      end

      :ok
    end
  else
    defp register_name_for_observer(_name), do: :ok
  end

  @doc """
  Generates observability data needed for reporting links and their metrics.

  If optionally turned on by setting `unsafely_name_processes_for_observer: :links` in
  config.exs, starts processes to reflect pads structure in the process tree for visibility
  in Erlang observer.
  """
  @spec generate_link_observability_data(Pad.ref(), link_observability_data()) ::
          link_observability_data()
  def generate_link_observability_data(pad_ref, other_observability_data \\ %{}) do
    %{
      path: ComponentPath.get(),
      observer_dbg_process: run_link_dbg_process(pad_ref, other_observability_data)
    }
  end

  if :links in @unsafely_name_processes_for_observer do
    defp run_link_dbg_process(pad_ref, observability_data) do
      {:ok, observer_dbg_process} =
        Task.start_link(fn ->
          Process.flag(:trap_exit, true)
          Process.register(self(), :"pad #{inspect(pad_ref)} #{:erlang.pid_to_list(self())}")
          process_to_link = Map.get(observability_data, :observer_dbg_process)
          if process_to_link, do: Process.link(process_to_link)

          receive do
            {:EXIT, _pid, _reason} -> :ok
          end
        end)

      observer_dbg_process
    end
  else
    defp run_link_dbg_process(_pad_ref, _observability_data), do: nil
  end

  @doc """
  Registers a link in the observer. Must be called by the sender element.
  """
  @spec register_link(t, Pad.ref(), Pad.ref(), link_observability_data()) :: :ok
  def register_link(observer, input_ref, output_ref, observability_data) do
    send(
      observer.pid,
      {:graph,
       %{
         entity: :link,
         from: observability_data.path,
         to: ComponentPath.get(),
         output: output_ref,
         input: input_ref
       }}
    )

    :ok
  end

  @doc """
  Unregisters a link in the observer. Can be called by both elements of the link.
  """
  @spec unregister_link(t, Pad.ref()) :: :ok
  def unregister_link(observer, pad_ref) do
    send(observer.pid, {:graph, %{entity: :remove_link, path: ComponentPath.get(), pad: pad_ref}})
    :ok
  end

  @doc """
  Subscribes for updates from the observer

  The following topics are supported:
  - graph - information about the shape of the pipeline, observer will send `t:graph_update/0` messages
  - metrics - metrics from pipeline components, observer will send `t:metrics_update/0` messages

  Subsequent subscription from the same process overrides any previous subscription. If the `confirm: id`
  option is passed, the observer will send a `{:subscribed, id}` message when the subscription is updated.
  """
  @spec subscribe(
          t(),
          [
            :graph
            | :metrics
            | {:graph, filter :: [entity: :component | :link, path: ComponentPath.path()]}
            | {:metrics, filter :: [path: ComponentPath.path()]}
          ],
          confirm: id :: term
        ) ::
          :ok
  def subscribe(observer, topics, opts \\ []) do
    send(observer.pid, {:subscribe, self(), topics, opts})
    :ok
  end

  if @metrics_enabled do
    defmacro report_metric(metric, value, opts \\ []) do
      quote do
        ets = Process.get(:__membrane_observer_ets__)

        if ets do
          :ets.insert(
            ets,
            {{unquote(metric), unquote(opts)[:component_path] || ComponentPath.get(),
              unquote(opts)[:id]}, unquote(value)}
          )
        end

        :ok
      end
    end

    defmacro report_metric_update(metric, init, fun, opts \\ []) do
      quote do
        ets = Process.get(:__membrane_observer_ets__)

        if ets do
          key =
            {unquote(metric), unquote(opts)[:component_path] || ComponentPath.get(),
             unquote(opts)[:id]}

          [{_key, value} | _default] = :ets.lookup(ets, key) ++ [{nil, unquote(init)}]

          :ets.insert(ets, {key, unquote(fun).(value)})
        end
      end
    end
  else
    defmacro report(metric, value, opts \\ []) do
      quote do
        fn ->
          _unused = unquote(metric)
          _unused = unquote(value)
          _unused = unquote(opts)
        end

        :ok
      end
    end

    defmacro report_update(metric, init, fun, opts \\ []) do
      quote do
        fn ->
          _unused = unquote(metric)
          _unused = unquote(init)
          _unused = unquote(fun)
          _unused = unquote(opts)
        end

        :ok
      end
    end
  end

  @impl true
  def init(%{ets: ets}) do
    Process.send_after(self(), :scrape_metrics, @scrape_interval)

    {:ok,
     %{
       ets: ets,
       graph: [],
       pid_to_component: %{},
       subscribers: %{},
       metrics: %{},
       timestamp: nil,
       init_time: System.monotonic_time(:millisecond)
     }}
  end

  @impl true
  def handle_info(:scrape_metrics, state) do
    Process.send_after(self(), :scrape_metrics, @scrape_interval)
    metrics = :ets.tab2list(state.ets)
    timestamp = System.monotonic_time(:millisecond) - state.init_time
    derivatives = calc_derivatives(metrics, timestamp, state)
    send_to_subscribers(metrics ++ derivatives, :metrics, &{:metrics, &1, timestamp}, state)
    {:noreply, %{state | metrics: Map.new(metrics), timestamp: timestamp}}
  end

  @impl true
  def handle_info({:graph, graph_update}, state) do
    {action, graph_entries, graph_updates, state} = handle_graph_update(graph_update, state)
    send_to_subscribers(graph_updates, :graph, &{:graph, action, &1}, state)
    {:noreply, %{state | graph: graph_entries ++ state.graph}}
  end

  @impl true
  def handle_info({:subscribe, pid, topics, opts}, state) do
    _ref = unless Map.has_key?(state.subscribers, pid), do: Process.monitor(pid)
    opts = Keyword.validate!(opts, [:confirm])
    with {:ok, id} <- Keyword.fetch(opts, :confirm), do: send(pid, {:subscribed, id})

    topics =
      Map.new(topics, fn
        {:graph, constraints} ->
          constraints = Map.new(constraints)
          entity_constraint = Map.get(constraints, :entity)
          path_constraint = Map.get(constraints, :path)

          filter = fn
            %{entity: :component, path: path} ->
              entity_constraint in [:component, nil] and path_constraint in [path, nil]

            %{entity: :link, from: from, to: to} ->
              entity_constraint in [:link, nil] and path_constraint in [from, to, nil]
          end

          {:graph, filter}

        {:metrics, constraints} ->
          constraints = Map.new(constraints)
          path_constraint = Map.get(constraints, :path)
          filter = fn {{_metric, path, _pad}, _value} -> path_constraint in [path, nil] end
          {:metrics, filter}

        topic ->
          {topic, fn _value -> true end}
      end)

    state = put_in(state, [:subscribers, pid], topics)

    with %{graph: filter} <- topics do
      graph = state.graph |> Enum.reverse() |> Enum.filter(filter)
      send(pid, {:graph, :add, graph})
      :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    cond do
      Map.has_key?(state.subscribers, pid) ->
        {:noreply, Bunch.Access.delete_in(state, [:subscribers, pid])}

      Map.has_key?(state.pid_to_component, pid) ->
        handle_info({:graph, %{entity: :remove_component, pid: pid}}, state)

      true ->
        {:noreply, state}
    end
  end

  defp send_to_subscribers(values, topic, transform, state) do
    Enum.each(state.subscribers, fn
      {pid, %{^topic => filter}} ->
        values = Enum.filter(values, filter)
        if values != [], do: send(pid, transform.(values))

      _subscriber ->
        :ok
    end)
  end

  defp handle_graph_update(%{entity: :component, pid: pid} = update, state) do
    Process.monitor(pid)
    {:add, [update], [update], put_in(state, [:pid_to_component, pid], update)}
  end

  defp handle_graph_update(%{entity: :remove_component, pid: pid}, state) do
    {update, state} = pop_in(state, [:pid_to_component, pid])
    graph = Enum.reject(state.graph, &(&1.entity == :component and update.path == &1.path))

    {removed_links, graph} =
      Enum.split_with(graph, &(&1.entity == :link and update.path in [&1.from, &1.to]))

    removed_links =
      Enum.map(removed_links, fn link ->
        link |> Map.take([:from, :to, :output, :input]) |> Map.put(:entity, :link)
      end)

    {:remove, [], removed_links ++ [update], %{state | graph: graph}}
  end

  defp handle_graph_update(%{entity: :link} = update, state) do
    {:add, [update], [update], state}
  end

  defp handle_graph_update(%{entity: :remove_link, path: path, pad: pad}, state) do
    {removed_links, graph} =
      Enum.split_with(
        state.graph,
        &(&1.entity == :link and {path, pad} in [{&1.from, &1.output}, {&1.to, &1.input}])
      )

    removed_links =
      Enum.map(removed_links, fn link ->
        link |> Map.take([:from, :to, :output, :input]) |> Map.put(:entity, :link)
      end)

    {:remove, [], removed_links, %{state | graph: graph}}
  end

  defp calc_derivatives(_new_metrics, _new_timestamp, %{timestamp: nil}) do
    []
  end

  defp calc_derivatives(new_metrics, new_timestamp, %{metrics: metrics, timestamp: timestamp}) do
    dt_seconds = (new_timestamp - timestamp) / 1000

    new_metrics
    |> Enum.filter(fn {k, _v} -> Map.has_key?(metrics, k) end)
    |> Enum.map(fn {{metric, path, pad} = k, value} ->
      {{"#{metric} dt", path, pad}, (value - metrics[k]) / dt_seconds}
    end)
  end
end
