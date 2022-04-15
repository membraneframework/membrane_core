defmodule Membrane.Testing.Pipeline do
  @moduledoc """
  This Pipeline was created to reduce testing boilerplate and ease communication
  with its elements. It also provides a utility for informing testing process about
  playback state changes and received notifications.

  When you want a build Pipeline to test your elements you need three things:
   - Pipeline Module
   - List of elements
   - Links between those elements

  When creating pipelines for tests the only essential part is the list of
   elements. In most cases during the tests, elements are linked in a way that
  `:output` pad is linked to `:input` pad of subsequent element. So we only need
   to pass a list of elements and links can be generated automatically.

  To start a testing pipeline you need to build
  `Membrane.Testing.Pipeline.Options` struct and pass to
  `Membrane.Testing.Pipeline.start_link/2`. Links are generated by
  `populate_links/1`.

  ```
  options = %Membrane.Testing.Pipeline.Options {
    elements: [
      el1: MembraneElement1,
      el2: MembraneElement2,
      ...
    ]
  }
  {:ok, pipeline} = Membrane.Testing.Pipeline.start_link(options)
  ```

  If you need to pass custom links, you can always do it using `:links` field of
  `Membrane.Testing.Pipeline.Options` struct.

  ```
  options = %Membrane.Testing.Pipeline.Options {
    elements: [
      el1: MembraneElement1,
      el2: MembraneElement2,
      ],
      links: [
        link(:el1) |> to(:el2)
      ]
    }
    ```

  You can also pass a custom pipeline module, by using `:module` field of
  `Membrane.Testing.Pipeline.Options` struct. Every callback of the module
  will be executed before the callbacks of Testing.Pipeline.
  Passed module has to return a proper spec. There should be no elements
  nor links specified in options passed to test pipeline as that would
  result in a failure.

  ```
  options = %Membrane.Testing.Pipeline.Options {
      module: Your.Module
  }
  ```

  See `Membrane.Testing.Pipeline.Options` for available options.

  ## Assertions

  This pipeline is designed to work with `Membrane.Testing.Assertions`. Check
  them out or see example below for more details.

  ## Messaging children

  You can send messages to children using their names specified in the elements
  list. Please check `message_child/3` for more details.

  ## Example usage

  Firstly, we can start the pipeline providing its options:

      options = %Membrane.Testing.Pipeline.Options {
        elements: [
          source: %Membrane.Testing.Source{},
          tested_element: TestedElement,
          sink: %Membrane.Testing.Sink{}
        ]
      }
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
    Structure representing `options` passed to testing pipeline.

    ## Struct fields

    - `:test_process` - `pid` of process that shall receive messages from testing pipeline, e.g. when pipeline's playback state changes.
      This allows using `Membrane.Testing.Assertions`
    - `:elements` - a list of element specs. Allows to create a simple pipeline without defining a module for it.
    - `:links` - a list describing the links between elements. If ommited (or set to `nil`), they will be populated automatically
      based on the elements order using default pad names.
    - `:module` - pipeline module with custom callbacks - useful if a simple list of elements is not enough.
    - `:custom_args`- arguments for the module's `handle_init` callback.
    """

    defstruct [:elements, :links, :test_process, :module, :custom_args]

    @type t :: %__MODULE__{
            test_process: pid() | nil,
            elements: ParentSpec.children_spec_t() | nil,
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

  @spec start_link(Options.t(), GenServer.options()) :: GenServer.on_start()
  def start_link(pipeline_options, process_options \\ []) do
    do_start(:start_link, pipeline_options, process_options)
  end

  @spec start(Options.t(), GenServer.options()) :: GenServer.on_start()
  def start(pipeline_options, process_options \\ []) do
    do_start(:start, pipeline_options, process_options)
  end

  defp do_start(_type, %Options{elements: nil, module: nil}, _process_options) do
    raise """

    You provided no information about pipeline contents. Please provide either:
     - list of elements via `elements` field of Options struct with optional links between
     them via `links` field of `Options` struct
     - module that implements `Membrane.Pipeline` callbacks via `module` field of `Options`
     struct
    """
  end

  defp do_start(_type, %Options{elements: elements, module: module}, _process_options)
       when is_atom(module) and module != nil and elements != nil do
    raise """

    When working with Membrane.Testing.Pipeline you can't provide both
    override module and elements list in the Membrane.Testing.Pipeline.Options
    struct.
    """
  end

  defp do_start(type, options, process_options) do
    pipeline_options = default_options(options)
    args = [__MODULE__, pipeline_options, process_options]
    apply(Pipeline, type, args)
  end

  @doc """
  Links subsequent elements using default pads (linking `:input` to `:output` of
  previous element).

  ## Example

      Pipeline.populate_links([el1: MembraneElement1, el2: MembraneElement2])
  """
  @spec populate_links(elements :: ParentSpec.children_spec_t()) :: ParentSpec.links_spec_t()
  def populate_links(elements) when length(elements) < 2 do
    []
  end

  def populate_links(elements) when is_list(elements) do
    import ParentSpec
    [h | t] = elements |> Keyword.keys()
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
    new_links = populate_links(options.elements)
    handle_init(%Options{options | links: new_links})
  end

  @impl true
  def handle_init(%Options{module: nil} = options) do
    spec = %Membrane.ParentSpec{
      children: options.elements,
      links: options.links
    }

    new_state = %State{test_process: options.test_process, module: nil}
    {{:ok, [spec: spec, playback: :playing]}, new_state}
  end

  @impl true
  def handle_init(%Options{links: nil, elements: nil} = options) do
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
  def handle_spec_started(elements, ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_spec_started,
        [elements, ctx],
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
  def handle_call(message, ctx, state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_call,
        [message, ctx],
        state
      )

    :ok = notify_test_process(state.test_process, {:handle_call, message})

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
