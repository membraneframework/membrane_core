defmodule Membrane.Testing.PipelineTest do
  use ExUnit.Case

  import  Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing.Pipeline
  alias Membrane.Child

  defmodule Elem do
    use Membrane.Filter
  end

  defmodule MockPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, _opts), do: {[spec: []], :state}
  end

  describe "Testing pipeline creation" do
    test "works with :default implementation" do
      elements = [elem: Elem, elem2: Elem]
      links = [get_child(:elem) |> get_child(:elem2)]
      options = [module: :default, spec: elements ++ links, test_process: nil]
      assert {[spec: spec, playback: :playing], state} = Pipeline.handle_init(%{}, options)

      assert state == %Pipeline.State{module: nil, test_process: nil}

      assert spec == elements ++ links
    end

    test "by default chooses :default implementation" do
      links = [child(:elem, Elem) |> child(:elem2, Elem)]
      options = [module: :default, spec: links, test_process: nil]
      assert {[spec: spec, playback: :playing], state} = Pipeline.handle_init(%{}, options)
      assert state == %Pipeline.State{module: nil, test_process: nil}

      assert spec == links
    end

    test "works with custom module injected" do
      options = [module: MockPipeline, test_process: nil, custom_args: []]
      assert {[spec: spec], state} = Pipeline.handle_init(%{}, options)
      assert spec == []

      assert state == %Pipeline.State{
               custom_pipeline_state: :state,
               module: MockPipeline,
               test_process: nil
             }
    end
  end

  describe "When initializing Testing Pipeline" do
    test "uses prepared links if they were provided" do

      links = [child(:elem, Elem) |> child(:elem2, Elem)]
      options = [module: :default, spec: links, test_process: nil]
      assert {[spec: spec, playback: :playing], state} = Pipeline.handle_init(%{}, options)
      assert state == %Pipeline.State{module: nil, test_process: nil}

      assert spec == links
    end
  end

  describe "When starting, Testing Pipeline" do
    test "exits with an error if not a module or non-existing module was passed" do
      Process.flag(:trap_exit, true)
      Pipeline.start_link(module: [1, 2])
      assert_receive {:EXIT, _pid, {exception, stacktrace}}
      assert_raise RuntimeError, ~r/Not a module./, fn -> reraise exception, stacktrace end
      Pipeline.start_link(module: NotExistingModule)
      assert_receive {:EXIT, _pid, {exception, stacktrace}}
      assert_raise RuntimeError, ~r/Unknown module./, fn -> reraise exception, stacktrace end
    end
  end

  test "get_child_pid/3" do
    defmodule Element do
      use Membrane.Filter

      @impl true
      def handle_parent_notification({:get_pid, msg_id}, _ctx, state) do
        {[notify_parent: {:pid, self(), msg_id}], state}
      end
    end

    defmodule Bin do
      use Membrane.Bin

      @impl true
      def handle_init(_ctx, _opts) do
        spec = [
          child(:element_1, Element),
          child(:element_2, Element),
          child(:element_3, Element)
        ]

        {[spec: spec], %{}}
      end

      @impl true
      def handle_parent_notification({:get_pid, msg_id}, _ctx, state) do
        {[notify_parent: {:pid, self(), msg_id}], state}
      end

      @impl true
      def handle_parent_notification({:get_child_pid, child, msg_id}, _ctx, state) do
        {[notify_child: {child, {:get_pid, msg_id}}], state}
      end

      @impl true
      def handle_child_notification(msg, _child, _ctx, state) do
        {[notify_parent: msg], state}
      end
    end

    spec = [
      child(:bin_1, Bin),
      child(:bin_2, Bin),
      child(:bin_3, Bin)
    ]

    pipeline = Pipeline.start_supervised!(spec: spec)

    assert_pipeline_play(pipeline)

    # getting children pids from pipeline
    for bin <- [:bin_1, :bin_2, :bin_3] do
      Pipeline.execute_actions(pipeline, notify_child: {bin, {:get_pid, bin}})
      assert_pipeline_notified(pipeline, bin, {:pid, bin_pid, ^bin})

      assert {:ok, bin_pid} == Pipeline.get_child_pid(pipeline, bin)
    end

    # getting children pids from bins
    for bin <- [:bin_1, :bin_2, :bin_3], element <- [:element_1, :element_2, :element_3] do
      Pipeline.execute_actions(pipeline,
        notify_child: {bin, {:get_child_pid, element, {bin, element}}}
      )

      assert_pipeline_notified(pipeline, bin, {:pid, element_pid, {^bin, ^element}})

      assert {:ok, element_pid} == Pipeline.get_child_pid(pipeline, [bin, element])
    end

    # getting pid of child from child group
    Pipeline.execute_actions(pipeline, spec: {child(:element, Element), group: :group})

    element_ref = Child.ref(:element, group: :group)

    Pipeline.execute_actions(pipeline,
      notify_child: {element_ref, {:get_pid, element_ref}}
    )

    assert_pipeline_notified(pipeline, element_ref, {:pid, element_pid, ^element_ref})

    assert {:ok, element_pid} == Pipeline.get_child_pid(pipeline, element_ref)

    # returning error tuple with proper reason
    assert {:error, :child_not_found} = Pipeline.get_child_pid(pipeline, :nonexisting_child)

    assert {:error, :element_cannot_have_children} =
             Pipeline.get_child_pid(pipeline, [element_ref, :child])

    monitor_ref = Process.monitor(pipeline)
    Pipeline.terminate(pipeline)
    assert_receive {:DOWN, ^monitor_ref, :process, ^pipeline, _reason}

    assert {:error, :pipeline_not_alive} = Pipeline.get_child_pid(pipeline, :bin_1)
  end
end
