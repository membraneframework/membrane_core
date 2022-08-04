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
  a keyword list representing the options used to determine the pipeline's behaviour and then
  pass that options list to the `Membrane.Testing.Pipeline.start_link/1`.
  The testing pipeline can be started in one of two modes - either with its `:default` behaviour, or by
  injecting a custom module behaviour. The usage of a `:default` pipeline implementation is presented below:

  ```
  children = [
      el1: MembraneElement1,
      el2: MembraneElement2,
      ...
  ]
  options =  [
    module: :default # :default is the default value for this parameter, so you do not need to pass it here
    links: Membrane.ParentSpec.link_linear(children)
  ]
  {:ok, pipeline} = Membrane.Testing.Pipeline.start_link(options)
  ```
  Note, that we have used `Membrane.Testing.ParentSpec.link_linear/1` function, that creates the list of links
  for the given list of children, linking them in linear manner (that means - children are linked in a way that
  `:output` pad of a given child is linked to `:input` pad of subsequent child). That is the case
  which is often used while creating testing pipelines. Be aware, that `Membrane.Testing.ParentSpec.link_linear/1`
  creates also a children specification itself, which means, that you cannot pass that children specification
  as another option's argument (adding `children: children` option would lead to a duplication of children specifications).
  If you need to link children in a different manner, you can of course do it by passing an appropriate list
  of links as a `:links` option, just as you would do with a regular pipeline.

  You can also pass your custom pipeline's module as a `:module` option of
  the options list. Every callback of the module
  will be executed before the callbacks of Testing.Pipeline.
  Passed module has to return a proper spec. There should be no children
  nor links specified in options passed to test pipeline as that would
  result in a failure.

  ```
  options = [
    module: Your.Module
  ]
  {:ok, pipeline} = Membrane.Testing.Pipeline.start_link(options)
  ```

  See `Membrane.Testing.Pipeline.pipeline_keyword_list_t()` for available options.

  ## Assertions

  This pipeline is designed to work with `Membrane.Testing.Assertions`. Check
  them out or see example below for more details.

  ## Messaging children

  You can send messages to children using their names specified in the children
  list. Please check `message_child/3` for more details.

  ## Example usage

  Firstly, we can start the pipeline providing its options as a keyword list:
      children = [
          source: %Membrane.Testing.Source{},
          tested_element: TestedElement,
          sink: %Membrane.Testing.Sink{}
      ]
      {:ok, pipeline} = Membrane.Testing.Pipeline.start_link(links: Membrane.ParentSpec.link_linear(children))

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

  require Membrane.Logger

  defmodule State do
    @moduledoc false
    # Structure representing `state`.

    # ##  Test Process
    # `pid` of process that shall receive messages when Pipeline invokes playback
    # state change callback and receives notification.

    # ## Module
    # Pipeline Module with custom callbacks.

    # ## Custom Pipeline State
    # State of the pipeline defined by Module.

    @enforce_keys [:test_process, :module]
    defstruct @enforce_keys ++ [:custom_pipeline_state]

    @type t :: %__MODULE__{
            test_process: pid() | nil,
            module: module() | nil,
            custom_pipeline_state: Pipeline.state()
          }
  end

  @type options ::
          [
            module: :default,
            children: ParentSpec.children_spec_t(),
            links: ParentSpec.links_spec_t(),
            test_process: pid(),
            name: Pipeline.name()
          ]
          | [
              module: module(),
              custom_args: Pipeline.pipeline_options(),
              test_process: pid(),
              name: Pipeline.name()
            ]

  @spec child_spec(options) :: Supervisor.child_spec()
  def child_spec(options) do
    id = Keyword.get(options, :name, make_ref())
    super(options) |> Map.merge(%{restart: :transient, id: id})
  end

  @spec start_link(options) :: Pipeline.on_start()
  def start_link(options) do
    do_start(:start_link, options)
  end

  @spec start(options) :: Pipeline.on_start()
  def start(options) do
    do_start(:start, options)
  end

  if Mix.env() == :test do
    @spec start_link_supervised(options) :: Pipeline.on_start()
    def start_link_supervised(pipeline_options \\ []) do
      pipeline_options = Keyword.put_new(pipeline_options, :test_process, self())

      # TODO use start_link_supervised when added
      with {:ok, supervisor, pipeline} <-
             ExUnit.Callbacks.start_supervised({__MODULE__, pipeline_options}) do
        Process.link(pipeline)
        {:ok, supervisor, pipeline}
      else
        {:error, {error, _child_info}} -> {:error, error}
      end
    end

    @spec start_link_supervised!(options) :: pipeline_pid :: pid
    def start_link_supervised!(pipeline_options \\ []) do
      {:ok, _supervisor, pipeline} = start_link_supervised(pipeline_options)
      pipeline
    end

    @spec start_supervised(options) :: Pipeline.on_start()
    def start_supervised(pipeline_options \\ []) do
      pipeline_options = Keyword.put_new(pipeline_options, :test_process, self())
      ExUnit.Callbacks.start_supervised({__MODULE__, pipeline_options})
    end

    @spec start_supervised!(options) :: pipeline_pid :: pid
    def start_supervised!(pipeline_options \\ []) do
      {:ok, _supervisor, pipeline} = start_supervised(pipeline_options)
      pipeline
    end
  end

  defp do_start(type, options) do
    {process_options, options} = Keyword.split(options, [:name])
    options = Keyword.put_new(options, :test_process, self())
    apply(Pipeline, type, [__MODULE__, options, process_options])
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

  The actions are returned from the `handle_info` callback.
  """
  @spec execute_actions(pid(), Keyword.t()) :: :ok
  def execute_actions(pipeline, actions) do
    send(pipeline, {__MODULE__, :__execute_actions__, actions})
    :ok
  end

  @impl true
  def handle_init(options) do
    case Keyword.get(options, :module, :default) do
      :default ->
        spec = %Membrane.ParentSpec{
          children: Keyword.get(options, :children, []),
          links: Keyword.get(options, :links, [])
        }

        new_state = %State{test_process: Keyword.fetch!(options, :test_process), module: nil}
        {{:ok, [spec: spec, playback: :playing]}, new_state}

      module when is_atom(module) ->
        case Code.ensure_compiled(module) do
          {:module, _} -> :ok
          {:error, _} -> raise "Unknown module: #{inspect(module)}"
        end

        new_state = %State{
          module: module,
          custom_pipeline_state: Keyword.get(options, :custom_args),
          test_process: Keyword.fetch!(options, :test_process)
        }

        injected_module_result = eval_injected_module_callback(:handle_init, [], new_state)
        testing_pipeline_result = {:ok, new_state}
        combine_results(injected_module_result, testing_pipeline_result)

      not_a_module ->
        raise "Not a module: #{inspect(not_a_module)}"
    end
  end

  @impl true
  def handle_setup(ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_setup,
        [ctx],
        state
      )

    :ok = notify_test_process(state.test_process, :setup)

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_play(ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_play,
        [ctx],
        state
      )

    :ok = notify_test_process(state.test_process, :play)

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_child_notification(
        %Notification{payload: notification},
        from,
        _ctx,
        %State{} = state
      ) do
    :ok =
      notify_test_process(state.test_process, {:handle_child_notification, {notification, from}})

    {:ok, state}
  end

  @impl true
  def handle_child_notification(notification, from, ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_child_notification,
        [notification, from, ctx],
        state
      )

    :ok =
      notify_test_process(state.test_process, {:handle_child_notification, {notification, from}})

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
  def handle_info({__MODULE__, :__execute_actions__, actions}, _ctx, %State{} = state) do
    {{:ok, actions}, state}
  end

  @impl true
  def handle_info({:for_element, element, message}, ctx, %State{} = state) do
    injected_module_result =
      eval_injected_module_callback(
        :handle_info,
        [{:for_element, element, message}, ctx],
        state
      )

    testing_pipeline_result = {{:ok, notify_child: {element, message}}, state}

    combine_results(injected_module_result, testing_pipeline_result)
  end

  @impl true
  def handle_info(message, ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_info,
        [message, ctx],
        state
      )

    :ok = notify_test_process(state.test_process, {:handle_info, message})

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
  def handle_element_start_of_stream(element, pad, ctx, state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_element_start_of_stream,
        [element, pad, ctx],
        state
      )

    :ok =
      notify_test_process(state.test_process, {:handle_element_start_of_stream, {element, pad}})

    {custom_actions, Map.put(state, :custom_pipeline_state, custom_state)}
  end

  @impl true
  def handle_element_end_of_stream(element, pad, ctx, state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_element_end_of_stream,
        [element, pad, ctx],
        state
      )

    :ok = notify_test_process(state.test_process, {:handle_element_end_of_stream, {element, pad}})

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

  defp eval_injected_module_callback(callback, args, state)

  defp eval_injected_module_callback(_callback, _args, %State{module: nil} = state),
    do: {:ok, state} |> unify_result()

  defp eval_injected_module_callback(callback, args, state) do
    apply(state.module, callback, args ++ [state.custom_pipeline_state]) |> unify_result()
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
