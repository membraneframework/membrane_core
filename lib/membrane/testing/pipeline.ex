defmodule Membrane.Testing.Pipeline do
  @moduledoc """
  This Pipeline was created to reduce testing boilerplate and ease communication
  with its children. It also provides a utility for informing testing process about
  playback state changes and received notifications.

  When you want a build Pipeline to test your children you need three things:
   - Pipeline Module
   - List of children
   - Links between those children

  To start a testing pipeline you need to build
  a keywords list representing the options used to determine the pipeline's behaviour and then
  pass that options list to the `Membrane.Testing.Pipeline.start_link/2`.
  The testing pipeline can started in one of two modes - either with its `:default` behaviour, or by
  injecting a `:custom` module behaviour.  The usage of a `:default` mode is presented below:

  ```
  children = [
      el1: MembraneElement1,
      el2: MembraneElement2,
      ...
  ]
  options =  [
    mode: :default,
    children: children,
    links: Membrane.Testing.Pipeline.populate_links(children)
  ]
  {:ok, pipeline} = Membrane.Testing.Pipeline.start_link(options)
  ```
  Note, that we have used `Membrane.Testing.Pipeline.populate_links/1` function, that creates the list of links
  for the given list of children, linking them in linear manner (that means - children are linked in a way that
  `:output` pad of a given child is linked to `:input` pad of subsequent child). That is the case
  which is often used while creating testing pipelines.
  If you need to link children in a different manner, you can of course do it by passing an appropriate list
  of links as a `:links` option, just as you would do with a regular pipeline.

  With the `:custom` mode, you can pass your custom pipeline's module as a `:module` option of
  the options list. Every callback of the module
  will be executed before the callbacks of Testing.Pipeline.
  Passed module has to return a proper spec. There should be no children
  nor links specified in options passed to test pipeline as that would
  result in a failure.

  ```
  options = [
    mode: :custom,
    module: Your.Module
  ]
  {:ok, pipeline} = Membrane.Testing.Pipeline.start_link(options)
  ```

  See `Membrane.Testing.Pipeline.pipeline_keywords_list_t()` for available options.

  ## Assertions

  This pipeline is designed to work with `Membrane.Testing.Assertions`. Check
  them out or see example below for more details.

  ## Messaging children

  You can send messages to children using their names specified in the children
  list. Please check `message_child/3` for more details.

  ## Example usage

  Firstly, we can start the pipeline providing its options as a keywords list:
      children = [
          source: %Membrane.Testing.Source{},
          tested_element: TestedElement,
          sink: %Membrane.Testing.Sink{}
      ]
      options = [
        mode: :default,
        children: children,
        links: Membrane.Testing.Pipeline.populate_links(children)
      ]
      {:ok, pipeline} = Membrane.Testing.Pipeline.start_link(options)

  We can now wait till the end of the stream reaches the sink element (don't forget
  to import `Membrane.Testing.Assertions`):

      assert_end_of_stream(pipeline, :sink)

  We can also assert that the `Membrane.Testing.Sink` processed a specific
  buffer:

      assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: 1})

  """

  use Membrane.Pipeline

  alias Membrane.{Element, Pipeline}
  alias Membrane.ParentSpec
  alias Membrane.Testing.Notification

  defmodule Options do
    @moduledoc """
    @deprecated
    Structure representing `options` passed to testing pipeline.

    ## Struct fields

    - `:test_process` - `pid` of process that shall receive messages from testing pipeline, e.g. when pipeline's playback state changes.
      This allows using `Membrane.Testing.Assertions`
    - `:children` - a list of element specs. Allows to create a simple pipeline without defining a module for it.
    - `:links` - a list describing the links between children. If ommited (or set to `nil`), they will be populated automatically
      based on the children order using default pad names.
    - `:module` - pipeline module with custom callbacks - useful if a simple list of children is not enough.
    - `:custom_args`- arguments for the module's `handle_init` callback.
    """

    defstruct [:children, :links, :test_process, :module, :custom_args]

    @type t :: %__MODULE__{
            test_process: pid() | nil,
            children: ParentSpec.children_spec_t() | nil,
            links: ParentSpec.links_spec_t() | nil,
            module: module() | nil,
            custom_args: Pipeline.pipeline_options_t() | nil
          }
  end

  defmodule State do
    @moduledoc """
    Structure representing `state`.

    ##  Test Process
    `pid` of process that shall receive messages when Pipeline invokes playback
    state change callback and receives notification.

    ## Module
    Pipeline Module with custom callbacks.

    ## Custom Pipeline State
    State of the pipeline defined by Module.
    """

    @enforce_keys [:test_process, :module]
    defstruct @enforce_keys ++ [:custom_pipeline_state]

    @type t :: %__MODULE__{
            test_process: pid() | nil,
            module: module() | nil,
            custom_pipeline_state: any
          }
  end

  @type default_pipeline_keywords_list_t :: [
          children: ParentSpec.children_spec_t(),
          links: ParentSpec.links_spec_t(),
          test_process: pid() | nil
        ]
  @type custom_pipeline_keywords_list_t :: [
          module: module(),
          custom_args: Pipeline.pipeline_options_t() | nil,
          test_process: pid() | nil
        ]
  @type pipeline_keywords_list_t ::
          default_pipeline_keywords_list_t() | custom_pipeline_keywords_list_t()

  @spec start_link(Options.t() | pipeline_keywords_list_t(), GenServer.options()) ::
          GenServer.on_start()
  def start_link(pipeline_options, process_options \\ [])

  def start_link(pipeline_options, process_options) when is_struct(pipeline_options, Options) do
    IO.warn(
      "Please pass options to Membrane.Testing.Pipeline.start_link/2 as keywords list, instead of using Membrane.Testing.Options"
    )

    do_start(:start_link, pipeline_options, process_options)
  end

  def start_link(pipeline_options, process_options) do
    pipeline_options = transform_pipeline_options(pipeline_options)
    do_start(:start_link, pipeline_options, process_options)
  end

  @spec start(Options.t() | pipeline_keywords_list_t(), GenServer.options()) ::
          GenServer.on_start()
  def start(pipeline_options, process_options \\ [])

  def start(pipeline_options, process_options) when is_struct(pipeline_options, Options) do
    IO.warn(
      "Please pass options to Membrane.Testing.Pipeline.start/2 as keywords list, instead of using Membrane.Testing.Options"
    )

    do_start(:start, pipeline_options, process_options)
  end

  def start(pipeline_options, process_options) do
    pipeline_options = transform_pipeline_options(pipeline_options)
    do_start(:start, pipeline_options, process_options)
  end

  defp transform_pipeline_options(pipeline_options) do
    mode = Keyword.fetch!(pipeline_options, :mode)

    case mode do
      :default ->
        children = Keyword.fetch!(pipeline_options, :children)
        links = Keyword.fetch!(pipeline_options, :links)
        test_process = Keyword.get(pipeline_options, :test_process)
        %{mode: mode, children: children, links: links, test_process: test_process}

      :custom ->
        module = Keyword.fetch!(pipeline_options, :module)
        custom_args = Keyword.get(pipeline_options, :custom_args)
        test_process = Keyword.get(pipeline_options, :test_process)
        %{mode: mode, module: module, custom_args: custom_args, test_process: test_process}

      other_mode ->
        raise "Unknown testing pipeline mode #{other_mode}. Available modes are: :custom and :default"
    end
  end

  defp do_start(_type, %Options{children: nil, module: nil}, _process_options) do
    raise """

    You provided no information about pipeline contents. Please provide either:
     - list of elemenst via `children` field of Options struct with optional links between
     them via `links` field of `Options` struct
     - module that implements `Membrane.Pipeline` callbacks via `module` field of `Options`
     struct
    """
  end

  defp do_start(_type, %Options{children: children, module: module}, _process_options)
       when is_atom(module) and module != nil and children != nil do
    raise """

    When working with Membrane.Testing.Pipeline you can't provide both
    override module and children list in the Membrane.Testing.Pipeline.Options
    struct.
    """
  end

  defp do_start(type, options, process_options) do
    pipeline_options = default_options(options)
    args = [__MODULE__, pipeline_options, process_options]
    apply(Pipeline, type, args)
  end

  @doc """
  Links subsequent children using default pads (linking `:input` to `:output` of
  previous element).

  ## Example

      Pipeline.populate_links([el1: MembraneElement1, el2: MembraneElement2])
  """
  @spec populate_links(children :: ParentSpec.children_spec_t()) :: ParentSpec.links_spec_t()
  def populate_links(children) when length(children) < 2 do
    []
  end

  def populate_links(children) when is_list(children) do
    import ParentSpec
    [h | t] = children |> Keyword.keys()
    links = t |> Enum.reduce(link(h), &to(&2, &1))
    [links]
  end

  @doc """
  Sends message to a child by Element name.

  ## Example

  Knowing that `pipeline` has child named `sink`, message can be sent as follows:

      message_child(pipeline, :sink, {:message, "to handle"})
  """
  @spec message_child(pid(), Element.name_t(), any()) :: :ok
  def message_child(pipeline, child, message) do
    send(pipeline, {:for_element, child, message})
    :ok
  end

  @doc """
  Executes specified actions in the pipeline.

  The actions are returned from the `handle_other` callback.
  """
  @spec execute_actions(pid(), Keyword.t()) :: :ok
  def execute_actions(pipeline, actions) do
    send(pipeline, {:execute_actions, actions})
    :ok
  end

  @impl true
  def handle_init(%Options{links: nil, module: nil} = options) do
    new_links = populate_links(options.children)
    do_handle_init_for_default_implementation(%Options{options | links: new_links})
  end

  @impl true
  def handle_init(%Options{module: nil} = options) do
    do_handle_init_for_default_implementation(options)
  end

  @impl true
  def handle_init(%Options{links: nil, children: nil} = options) do
    do_handle_init_with_custom_module(options)
  end

  @impl true
  def handle_init(%{mode: :default} = options) do
    do_handle_init_for_default_implementation(options)
  end

  @impl true
  def handle_init(%{mode: :custom} = options) do
    do_handle_init_with_custom_module(options)
  end

  defp do_handle_init_for_default_implementation(options) do
    spec = %Membrane.ParentSpec{
      children: options.children,
      links: options.links
    }

    new_state = %State{test_process: options.test_process, module: nil}
    {{:ok, spec: spec}, new_state}
  end

  defp do_handle_init_with_custom_module(options) do
    new_state = %State{
      test_process: options.test_process,
      module: options.module,
      custom_pipeline_state: options.custom_args
    }

    injected_module_result = eval_injected_module_callback(:handle_init, [], new_state)
    testing_pipeline_result = {:ok, new_state}

    combine_results(injected_module_result, testing_pipeline_result)
  end

  @impl true
  def handle_stopped_to_prepared(ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_stopped_to_prepared,
        [ctx],
        state
      )

    :ok = notify_playback_state_changed(state.test_process, :stopped, :prepared)

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_prepared_to_playing(ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_prepared_to_playing,
        [ctx],
        state
      )

    :ok = notify_playback_state_changed(state.test_process, :prepared, :playing)

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_playing_to_prepared(ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_playing_to_prepared,
        [ctx],
        state
      )

    :ok = notify_playback_state_changed(state.test_process, :playing, :prepared)

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_prepared_to_stopped(ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_prepared_to_stopped,
        [ctx],
        state
      )

    :ok = notify_playback_state_changed(state.test_process, :prepared, :stopped)

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_notification(
        %Notification{payload: notification},
        from,
        _ctx,
        %State{} = state
      ) do
    :ok = notify_test_process(state.test_process, {:handle_notification, {notification, from}})
    {:ok, state}
  end

  @impl true
  def handle_notification(notification, from, ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_notification,
        [notification, from, ctx],
        state
      )

    :ok = notify_test_process(state.test_process, {:handle_notification, {notification, from}})

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_spec_started(children, ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_spec_started,
        [children, ctx],
        state
      )

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_other({:exec_actions, actions}, _ctx, %State{} = state) do
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:for_element, element, message}, ctx, %State{} = state) do
    injected_module_result =
      eval_injected_module_callback(
        :handle_other,
        [{:for_element, element, message}, ctx],
        state
      )

    testing_pipeline_result = {{:ok, forward: {element, message}}, state}

    combine_results(injected_module_result, testing_pipeline_result)
  end

  @impl true
  def handle_other({:execute_actions, actions}, ctx, %State{} = state) do
    injected_module_result =
      eval_injected_module_callback(
        :handle_other,
        [{:execute_actions, actions}, ctx],
        state
      )

    testing_pipeline_result = {{:ok, actions}, state}
    combine_results(injected_module_result, testing_pipeline_result)
  end

  @impl true
  def handle_other(message, ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_other,
        [message, ctx],
        state
      )

    :ok = notify_test_process(state.test_process, {:handle_other, message})

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_element_start_of_stream(endpoint, ctx, state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_element_start_of_stream,
        [endpoint, ctx],
        state
      )

    :ok = notify_test_process(state.test_process, {:handle_element_start_of_stream, endpoint})

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_element_end_of_stream(endpoint, ctx, state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_element_end_of_stream,
        [endpoint, ctx],
        state
      )

    :ok = notify_test_process(state.test_process, {:handle_element_end_of_stream, endpoint})

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_tick(timer, ctx, state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_tick,
        [timer, ctx],
        state
      )

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_crash_group_down(group_name, ctx, state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_crash_group_down,
        [group_name, ctx],
        state
      )

    :ok = notify_test_process(state.test_process, {:handle_crash_group_down, group_name})

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  defp default_options(%Options{test_process: nil} = options),
    do: %Options{options | test_process: self()}

  defp default_options(%{test_process: nil} = options),
    do: %{options | test_process: self()}

  defp default_options(options), do: options

  defp eval_injected_module_callback(callback, args, state)

  defp eval_injected_module_callback(_callback, _args, %State{module: nil} = state),
    do: {:ok, state} |> unify_result()

  defp eval_injected_module_callback(callback, args, state) do
    apply(state.module, callback, args ++ [state.custom_pipeline_state]) |> unify_result()
  end

  defp notify_playback_state_changed(test_process, previous, current) do
    notify_test_process(test_process, {:playback_state_changed, previous, current})
  end

  defp notify_test_process(test_process, message) do
    send(test_process, {__MODULE__, self(), message})
    :ok
  end

  defp unify_result({:ok, state}),
    do: {{:ok, []}, state}

  defp unify_result({{_, _}, _} = result),
    do: result

  defp combine_results({custom_actions, custom_state}, {actions, state}) do
    {combine_actions(custom_actions, actions),
     Map.put(state, :custom_pipeline_state, custom_state)}
  end

  defp combine_actions(l, r) do
    case {l, r} do
      {l, :ok} -> l
      {{:ok, actions_l}, {:ok, actions_r}} -> {:ok, actions_l ++ actions_r}
      {_l, r} -> r
    end
  end
end
