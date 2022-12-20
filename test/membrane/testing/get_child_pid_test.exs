defmodule Membrane.Testing.GetChildPidTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Child
  alias Membrane.Testing.Pipeline

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

  test "get_child_pid/3" do
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

    monitor_ref = Process.monitor(pipeline)
    Pipeline.terminate(pipeline)
    assert_receive {:DOWN, ^monitor_ref, :process, ^pipeline, _reason}

    assert {:error, :pipeline_not_alive} = Pipeline.get_child_pid(pipeline, :bin_1)
  end
end
