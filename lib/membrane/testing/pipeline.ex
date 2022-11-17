defmodule Membrane.Testing.Pipeline do
  @moduledoc """
  This Pipeline was created to reduce testing boilerplate and ease communication
  with its children. It also provides a utility for informing testing process about
  playback changes and received notifications.

  When you want a build Pipeline to test your children you need three things:
   - Pipeline Module
   - List of children
   - Links between those children

  To start a testing pipeline you need to build
  a keyword list representing the options used to determine the pipeline's behaviour and then
  pass that options list to the `Membrane.Testing.Pipeline.start_link_supervised!/1`.
  The testing pipeline can be started in one of two modes - either with its `:default` behaviour, or by
  injecting a custom module behaviour. The usage of a `:default` pipeline implementation is presented below:

  ```
  links = [
      child(:el1, MembraneElement1) |>
      child(:el2, MembraneElement2)
      ...
  ]
  options =  [
    module: :default # :default is the default value for this parameter, so you do not need to pass it here
    structure: links
  ]
  pipeline = Membrane.Testing.Pipeline.start_link_supervised!(options)
  ```

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
  pipeline = Membrane.Testing.Pipeline.start_link_supervised!(options)
  ```

  See `t:Membrane.Testing.Pipeline.options/0` for available options.

  ## Assertions

  This pipeline is designed to work with `Membrane.Testing.Assertions`. Check
  them out or see example below for more details.

  ## Messaging children

  You can send messages to children using their names specified in the children
  list. Please check `message_child/3` for more details.

  ## Example usage

  Firstly, we can start the pipeline providing its options as a keyword list:
    import Membrane.ChildrenSpec
    children = [
        child(source, %Membrane.Testing.Source{} ) |>
        child(:tested_element, TestedElement) |>
        child(sink, %Membrane.Testing.Sink{})
    ]
    {:ok, pipeline} = Membrane.Testing.Pipeline.start_link(structure: links)

  We can now wait till the end of the stream reaches the sink element (don't forget
  to import `Membrane.Testing.Assertions`):

      assert_end_of_stream(pipeline, :sink)

  We can also assert that the `Membrane.Testing.Sink` processed a specific
  buffer:

      assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: 1})

  """

  use Membrane.Pipeline

  alias Membrane.ChildrenSpec
  alias Membrane.{Element, Pipeline}
  alias Membrane.Testing.Notification

  require Membrane.Logger

  defmodule State do
    @moduledoc false

    @enforce_keys [:test_process, :module]
    defstruct @enforce_keys ++ [:custom_pipeline_state]

    @typedoc """
    Structure for holding state

    ##  Test Process
    `pid` of process that shall receive messages from the pipeline

    ## Module
    Pipeline Module with custom callbacks.

    ## Custom Pipeline State
    State of the pipeline defined by Module.
    """
    @type t :: %__MODULE__{
            test_process: pid() | nil,
            module: module() | nil,
            custom_pipeline_state: Pipeline.state()
          }
  end

  @type options ::
          [
            module: :default,
            structure: [ChildrenSpec.structure_builder_t()],
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

  defp do_start(type, options) do
    {process_options, options} = Keyword.split(options, [:name])
    options = Keyword.put_new(options, :test_process, self())
    apply(Pipeline, type, [__MODULE__, options, process_options])
  end

  @doc """
  Starts the pipeline under the ExUnit test supervisor and links it to the current process.

  Can be used only in tests.
  """
  @spec start_link_supervised(options) :: Pipeline.on_start()
  def start_link_supervised(pipeline_options \\ []) do
    pipeline_options = Keyword.put_new(pipeline_options, :test_process, self())

    # TODO use start_link_supervised when added
    with {:ok, supervisor, pipeline} <- ex_unit_start_supervised({__MODULE__, pipeline_options}) do
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

  @doc """
  Starts the pipeline under the ExUnit test supervisor.

  Can be used only in tests.
  """
  @spec start_supervised(options) :: Pipeline.on_start()
  def start_supervised(pipeline_options \\ []) do
    pipeline_options = Keyword.put_new(pipeline_options, :test_process, self())
    ex_unit_start_supervised({__MODULE__, pipeline_options})
  end

  @spec start_supervised!(options) :: pipeline_pid :: pid
  def start_supervised!(pipeline_options \\ []) do
    {:ok, _supervisor, pipeline} = start_supervised(pipeline_options)
    pipeline
  end

  defp ex_unit_start_supervised(child_spec) do
    # It's not a 'normal' call to keep dialyzer quiet
    apply(ExUnit.Callbacks, :start_supervised, [child_spec])
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
  def handle_init(ctx, options) do
    case Keyword.get(options, :module, :default) do
      :default ->
        structure = Bunch.listify(Keyword.get(options, :structure, []))

        spec = structure

        new_state = %State{test_process: Keyword.fetch!(options, :test_process), module: nil}
        {[spec: spec, playback: :playing], new_state}

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

        injected_module_result = eval_injected_module_callback(:handle_init, [ctx], new_state)
        testing_pipeline_result = {[], new_state}
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
  def handle_playing(ctx, %State{} = state) do
    {custom_actions, custom_state} =
      eval_injected_module_callback(
        :handle_playing,
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

    {[], state}
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
    {actions, state}
  end

  @impl true
  def handle_info({:for_element, element, message}, ctx, %State{} = state) do
    injected_module_result =
      eval_injected_module_callback(
        :handle_info,
        [{:for_element, element, message}, ctx],
        state
      )

    testing_pipeline_result = {[notify_child: {element, message}], state}

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
    do: {[], state}

  defp eval_injected_module_callback(callback, args, state) do
    apply(state.module, callback, args ++ [state.custom_pipeline_state])
  end

  defp notify_test_process(test_process, message) do
    send(test_process, {__MODULE__, self(), message})
    :ok
  end

  defp combine_results({custom_actions, custom_state}, {actions, state}) do
    {Enum.concat(custom_actions, actions), Map.put(state, :custom_pipeline_state, custom_state)}
  end
end
