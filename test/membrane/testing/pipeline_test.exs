defmodule Membrane.Testing.PipelineTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Child
  alias Membrane.Testing.Pipeline

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

      options = [
        module: :default,
        spec: elements ++ links,
        test_process: nil,
        raise_on_child_pad_removed?: false
      ]

      assert {[spec: spec], state} = Pipeline.handle_init(%{}, options)

      assert state == %Pipeline.State{
               module: nil,
               test_process: nil,
               raise_on_child_pad_removed?: false
             }

      assert spec == elements ++ links
    end

    test "by default chooses :default implementation" do
      links = [child(:elem, Elem) |> child(:elem2, Elem)]
      options = [module: :default, spec: links, test_process: nil]
      assert {[spec: spec], state} = Pipeline.handle_init(%{}, options)

      assert state == %Pipeline.State{
               module: nil,
               test_process: nil,
               raise_on_child_pad_removed?: true
             }

      assert spec == links
    end

    test "works with custom module injected" do
      options = [module: MockPipeline, test_process: nil, custom_args: []]
      assert {[spec: spec], state} = Pipeline.handle_init(%{}, options)
      assert spec == []

      assert state == %Pipeline.State{
               custom_pipeline_state: :state,
               module: MockPipeline,
               test_process: nil,
               raise_on_child_pad_removed?: nil
             }
    end
  end

  describe "When initializing Testing Pipeline" do
    test "uses prepared links if they were provided" do
      links = [child(:elem, Elem) |> child(:elem2, Elem)]
      options = [module: :default, spec: links, test_process: nil]
      assert {[spec: spec], state} = Pipeline.handle_init(%{}, options)

      assert state == %Pipeline.State{
               module: nil,
               test_process: nil,
               raise_on_child_pad_removed?: true
             }

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

    defmodule TripleElementBin do
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
      child(:bin_1, TripleElementBin),
      child(:bin_2, TripleElementBin),
      child(:bin_3, TripleElementBin)
    ]

    pipeline = Pipeline.start_supervised!(spec: spec)

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

  describe "Testing.Pipeline on handle_child_pad_removed" do
    defmodule DynamicElement do
      use Membrane.Endpoint

      def_input_pad :input,
        accepted_format: _any,
        availability: :on_request,
        flow_control: :push

      def_output_pad :output,
        accepted_format: _any,
        availability: :on_request,
        flow_control: :push

      @impl true
      def handle_pad_added(pad, _ctx, state) do
        {[notify_parent: {:pad_added, pad}], state}
      end
    end

    defmodule Bin do
      use Membrane.Bin

      alias Membrane.Testing.PipelineTest.DynamicElement

      require Membrane.Pad, as: Pad

      def_output_pad :output,
        accepted_format: _any,
        availability: :on_request

      @impl true
      def handle_pad_added(pad, _ctx, state) do
        spec =
          child(:element, DynamicElement)
          |> via_out(Pad.ref(:output, 1))
          |> bin_output(pad)

        {[spec: spec], state}
      end

      @impl true
      def handle_parent_notification(:remove_link, _ctx, state) do
        {[remove_link: {:element, Pad.ref(:output, 1)}], state}
      end
    end

    test "raises with option `:raise_on_child_pad_removed?` set to default" do
      spec =
        child(:bin, Bin)
        |> child(:sink, DynamicElement)

      pipeline = Pipeline.start_supervised!(spec: spec)
      monitor_ref = Process.monitor(pipeline)

      assert_pipeline_notified(pipeline, :sink, {:pad_added, _pad})
      Pipeline.execute_actions(pipeline, notify_child: {:bin, :remove_link})

      assert_receive {:DOWN, ^monitor_ref, :process, _pid, _reason}
    end

    test "doesn't raise with option `raise_on_child_pad_removed?: false`" do
      spec =
        child(:bin, Bin)
        |> child(:sink, DynamicElement)

      pipeline = Pipeline.start_supervised!(spec: spec, raise_on_child_pad_removed?: false)
      monitor_ref = Process.monitor(pipeline)

      assert_pipeline_notified(pipeline, :sink, {:pad_added, _pad})
      Pipeline.execute_actions(pipeline, notify_child: {:bin, :remove_link})

      refute_receive {:DOWN, ^monitor_ref, :process, _pid, _reason}
    end
  end
end
