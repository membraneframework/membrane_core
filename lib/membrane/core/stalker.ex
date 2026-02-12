defmodule Membrane.Core.Stalker do
  @moduledoc false

  use GenServer
  alias Membrane.{ComponentPath, Pad, Time}
  require Membrane.Core.Utils, as: Utils
  require Membrane.Logger

  @unsafely_name_processes_for_observer Application.compile_env(
                                          :membrane_core,
                                          :unsafely_name_processes_for_observer,
                                          []
                                        )

  @report_links_to_observer Application.compile_env(
                              :membrane_core,
                              :report_links_to_observer,
                              false
                            )

  @metrics_enabled Application.compile_env(:membrane_core, :enable_metrics, true)

  @scrape_interval 1000

  @function_metric :__membrane_stalker_function_metric__

  @enforce_keys [:pid, :ets]
  defstruct @enforce_keys

  @type component_config :: %{
          optional(:parent_path) => ComponentPath.path(),
          optional(:log_metadata) => Logger.metadata(),
          name: Membrane.Child.name(),
          component_type: :element | :bin | :pipeline
        }

  @type link_observability_data :: %{
          optional(:path) => ComponentPath.path(),
          optional(:observer_dbg_process) => pid | nil
        }

  @type graph_update ::
          {:graph, :add | :remove,
           [
             %{entity: :component, path: ComponentPath.path(), pid: pid}
             | %{
                 entity: :link,
                 from: ComponentPath.path(),
                 to: ComponentPath.path(),
                 output: Pad.ref(),
                 input: Pad.ref()
               }
           ]}

  @type metrics_update ::
          {:metrics, [{{metric :: atom, ComponentPath.path(), Pad.ref()}, value :: integer()}],
           timestamp_ms :: integer()}

  @type t :: %__MODULE__{pid: pid(), ets: :ets.tid() | nil}

  @doc false
  @spec start_link(%{ets: :ets.tid()}) :: {:ok, pid()}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Creates a new stalker and configures observability for the pipeline.

  Must be called by the pipeline process.
  """
  @spec new(component_config(), pid()) :: t()
  def new(config, supervisor) do
    {:ok, pid} =
      Membrane.Core.SubprocessSupervisor.start_utility(
        supervisor,
        {__MODULE__, %{pipeline: self()}}
      )

    ets = receive do: ({:ets, ets} -> ets)

    stalker = %__MODULE__{pid: pid, ets: ets}
    setup_process_local_observability(config, %{stalker: stalker})
    stalker
  end

  if @metrics_enabled do
    defp create_ets(), do: :ets.new(__MODULE__, [:public, write_concurrency: true])
  else
    defp create_ets(), do: nil
  end

  @doc """
  Registers a component in the stalker and configures the component's observability.

  Must be called by an element's or bin's process.
  """
  @spec register_component(t(), component_config()) :: :ok
  def register_component(stalker, config) do
    setup_process_local_observability(config, %{stalker: stalker})

    send(
      stalker.pid,
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
  # and labels the process with a meaningful name for easier introspection with stalker
  defp setup_process_local_observability(config, opts) do
    config = parse_observability_config(config, opts)

    # Metrics are currently reported only if the component
    # is on the same node as the pipeline
    if config.stalker && node(config.stalker.pid) == node(),
      do: Process.put(:__membrane_stalker_ets__, config.stalker.ets)

    if config.component_type == :pipeline and !config.is_utility,
      do: Process.put(:__membrane_pipeline__, true)

    Logger.metadata(config.log_metadata)
    set_label(config)

    ComponentPath.set(config.component_path)

    Membrane.Logger.set_prefix(ComponentPath.format(config.component_path) <> config.utility_name)

    :ok
  end

  defp parse_observability_config(config, opts) do
    utility_name = Map.get(opts, :utility_name)
    stalker = Map.get(opts, :stalker)
    %{name: name, component_type: component_type} = config
    is_utility = utility_name != nil

    name_string = if is_binary(name) and String.valid?(name), do: name, else: inspect(name)

    %{
      stalker: stalker,
      name: name,
      name_string: name_string,
      component_type: component_type,
      is_utility: is_utility,
      utility_name: if(is_utility, do: " #{utility_name}", else: ""),
      component_path: Map.get(config, :parent_path, []) ++ [name_string],
      log_metadata: Map.get(config, :log_metadata, [])
    }
  end

  defp set_label(config) do
    utility_str = if config.is_utility, do: "'s #{config.utility_name}", else: ""
    component_path_str = ComponentPath.format(config.component_path)

    label = "#{component_path_str}#{utility_str}"

    Process.set_label(label)
  end

  @doc """
  Generates observability data needed for reporting links and their metrics.

  If optionally turned on by setting `report_links_to_observer: true` in
  config.exs, starts processes to reflect pads structure in the process tree for visibility
  in Erlang observer.
  """
  @spec generate_observability_data_for_link(Pad.ref(), link_observability_data()) ::
          link_observability_data()
  def generate_observability_data_for_link(pad_ref, other_observability_data \\ %{}) do
    %{
      path: ComponentPath.get(),
      observer_dbg_process: run_link_dbg_process(pad_ref, other_observability_data)
    }
  end

  if :components in @unsafely_name_processes_for_observer do
    IO.warn("""
    Deprecated `:components` value for :unsafely_name_processes_for_observer` configuration.
    Now the processes are always labeled so there is no need to use this option anymore.
    """)
  end

  if :links in @unsafely_name_processes_for_observer do
    IO.warn("""
    Deprecated `:links` value for `:unsafely_name_processes_for_observer` configuration.
    Instead please use the following configuration:
    ```
    config :membrane_core, report_links_to_observer: true
    ```
    """)
  end

  if @report_links_to_observer do
    defp run_link_dbg_process(pad_ref, observability_data) do
      {:ok, observer_dbg_process} =
        Task.start_link(fn ->
          Process.flag(:trap_exit, true)
          Process.set_label(self(), "pad #{inspect(pad_ref)} #{:erlang.pid_to_list(self())}")
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
  Registers a link in the stalker. Must be called by the sender element.
  """
  @spec register_link(t, Pad.ref(), Pad.ref(), link_observability_data()) :: :ok
  def register_link(stalker, input_ref, output_ref, observability_data) do
    send(
      stalker.pid,
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
  Unregisters a link in the stalker. Can be called by both elements of the link.
  """
  @spec unregister_link(t, Pad.ref()) :: :ok
  def unregister_link(stalker, pad_ref) do
    send(stalker.pid, {:graph, %{entity: :remove_link, path: ComponentPath.get(), pad: pad_ref}})
    :ok
  end

  @doc """
  Subscribes for updates from the stalker

  The following topics are supported:
  - graph - information about the shape of the pipeline, stalker will send `t:graph_update/0` messages
  - metrics - metrics from pipeline components, stalker will send `t:metrics_update/0` messages

  Subsequent subscription from the same process overrides any previous subscription. If the `confirm: id`
  option is passed, the stalker will send a `{:subscribed, id}` message when the subscription is updated.
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
  def subscribe(stalker, topics, opts \\ []) do
    send(stalker.pid, {:subscribe, self(), topics, opts})
    :ok
  end

  if @metrics_enabled do
    defmacro report_metric(metric, value, opts \\ []) do
      try_insert(
        quote do
          {unquote(metric), unquote(opts)[:component_path] || ComponentPath.get(),
           unquote(opts)[:pad]}
        end,
        value
      )
    end

    defmacro register_metric_function(metric, function, opts \\ []) do
      try_insert(
        quote do
          {unquote(metric), unquote(opts)[:component_path] || ComponentPath.get(),
           unquote(opts)[:pad]}
        end,
        {@function_metric, function}
      )
    end
  else
    defmacro report_metric(metric, value, opts \\ []) do
      quote do
        fn ->
          _unused = unquote(metric)
          _unused = unquote(value)
          _unused = unquote(opts)
        end

        :ok
      end
    end

    defmacro register_metric_function(metric, function, opts \\ []) do
      quote do
        fn ->
          _unused = unquote(metric)
          _unused = unquote(function)
          _unused = unquote(opts)
        end

        :ok
      end
    end
  end

  defp try_insert(key, value) do
    quote do
      ets = Process.get(:__membrane_stalker_ets__)

      if ets do
        try do
          :ets.insert(ets, {unquote(key), unquote(value)})
        rescue
          error ->
            require Logger
            pretty_error = Exception.format(:error, error, __STACKTRACE__)

            Logger.debug("""
            Failed to insert a metric into the observability ETS.
            Error: #{pretty_error}
            """)
        end
      end

      :ok
    end
  end

  @impl true
  def init(options) do
    Utils.log_on_error do
      do_init(options)
    end
  end

  defp do_init(%{pipeline: pipeline}) do
    Process.send_after(self(), :scrape_metrics, @scrape_interval)
    ets = create_ets()
    send(pipeline, {:ets, ets})

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
  def handle_info(msg, state) do
    Utils.log_on_error do
      do_handle_info(msg, state)
    end
  end

  defp do_handle_info(:scrape_metrics, state) do
    Process.send_after(self(), :scrape_metrics, @scrape_interval)
    metrics = scrape_metrics(state)
    timestamp = Time.milliseconds(System.monotonic_time(:millisecond) - state.init_time)

    cond do
      state.timestamp == nil ->
        send_to_subscribers(metrics, :metrics, &{:metrics, &1, timestamp}, state)

      timestamp > state.timestamp ->
        derivatives = calc_derivatives(metrics, timestamp, state)
        send_to_subscribers(metrics ++ derivatives, :metrics, &{:metrics, &1, timestamp}, state)

      true ->
        # Since we're scraping metrics more or less every second, this should never
        # happen - but it does, very rarely, probably because of stalls caused by NIFs
        # running for too long and blocking schedulers.
        # This would lead to division by 0 in calc_derivatives.
        # In such a weird case, we skip reporting metrics.
        Membrane.Logger.debug("""
        [Membrane Stalker] Not reporting metrics due to unexpected timestamp: #{timestamp}, \
        previous timestamp: #{state.timestamp}. \
        This may indicate that some NIFs are running too long on regular schedulers \
        and make BEAM misbehave. Make sure all long-running NIFs are executed on \
        dirty schedulers.
        """)
    end

    {:noreply, %{state | metrics: Map.new(metrics), timestamp: timestamp}}
  end

  defp do_handle_info({:graph, graph_update}, state) do
    {action, graph_updates, state} = handle_graph_update(graph_update, state)
    send_to_subscribers(graph_updates, :graph, &{:graph, action, &1}, state)
    {:noreply, state}
  end

  defp do_handle_info({:subscribe, pid, topics, opts}, state) do
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

    _ignored =
      with %{graph: filter} <- topics do
        graph = state.graph |> Enum.reverse() |> Enum.filter(filter)
        send(pid, {:graph, :add, graph})
      end

    {:noreply, state}
  end

  defp do_handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
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
    state = put_in(state, [:pid_to_component, pid], update)
    state = %{state | graph: [update | state.graph]}
    {:add, [update], state}
  end

  defp handle_graph_update(%{entity: :remove_component, pid: pid}, state) do
    {update, state} = pop_in(state, [:pid_to_component, pid])
    cleanup_metrics({:_, update.path, :_}, state)
    graph = Enum.reject(state.graph, &(&1.entity == :component and update.path == &1.path))

    {removed_links, graph} =
      Enum.split_with(graph, &(&1.entity == :link and update.path in [&1.from, &1.to]))

    {:remove, removed_links ++ [update], %{state | graph: graph}}
  end

  defp handle_graph_update(%{entity: :link} = update, state) do
    {:add, [update], %{state | graph: [update | state.graph]}}
  end

  defp handle_graph_update(%{entity: :remove_link, path: path, pad: pad}, state) do
    {removed_links, graph} =
      Enum.split_with(
        state.graph,
        &(&1.entity == :link and {path, pad} in [{&1.from, &1.output}, {&1.to, &1.input}])
      )

    Enum.each(removed_links, fn link ->
      cleanup_metrics({:_, link.from, link.output}, state)
      cleanup_metrics({:_, link.to, link.input}, state)
    end)

    {:remove, removed_links, %{state | graph: graph}}
  end

  defp scrape_metrics(%{ets: nil}) do
    []
  end

  defp scrape_metrics(%{ets: ets}) do
    :ets.tab2list(ets)
    |> Enum.map(fn
      {key, {@function_metric, function}} -> {key, function.()}
      metric -> metric
    end)
  end

  defp cleanup_metrics(_pattern, %{ets: nil}) do
    :ok
  end

  defp cleanup_metrics(pattern, %{ets: ets}) do
    :ets.match_delete(ets, {pattern, :_})
    :ok
  end

  defp calc_derivatives(new_metrics, new_timestamp, %{metrics: metrics, timestamp: timestamp}) do
    dt_seconds = Time.as_seconds(new_timestamp - timestamp)

    new_metrics
    |> Enum.filter(fn {k, _v} -> Map.has_key?(metrics, k) end)
    |> Enum.map(fn {{metric, path, pad} = k, value} ->
      {{"#{metric} dt", path, pad}, Ratio.new(value - metrics[k], dt_seconds) |> Ratio.to_float()}
    end)
  end
end
