defmodule Membrane.ResourceGuardTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.{ResourceGuard, Testing}

  test "Resources are freed upon component termination" do
    defmodule Element do
      use Membrane.Source

      alias Membrane.ResourceGuard

      @impl true
      def handle_setup(ctx, state) do
        ResourceGuard.register(ctx.resource_guard, fn ->
          send(:membrane_resource_guard_test_process, :element_guard_triggered)
        end)

        {[notify_parent: :ready], state}
      end
    end

    defmodule Bin do
      use Membrane.Bin

      alias Membrane.ResourceGuard

      @impl true
      def handle_setup(ctx, state) do
        ResourceGuard.register(ctx.resource_guard, fn ->
          send(:membrane_resource_guard_test_process, :bin_guard_triggered)
        end)

        {[notify_parent: :ready], state}
      end
    end

    defmodule Pipeline do
      use Membrane.Pipeline

      alias Membrane.ResourceGuard

      @impl true
      def handle_call(:setup_guard, ctx, state) do
        ResourceGuard.register(ctx.resource_guard, fn ->
          send(:membrane_resource_guard_test_process, :pipeline_guard_triggered)
        end)

        {[reply: :ready], state}
      end
    end

    Process.register(self(), :membrane_resource_guard_test_process)

    pipeline = Testing.Pipeline.start_link_supervised!(module: Pipeline)

    Testing.Pipeline.execute_actions(pipeline,
      spec: [child(:element, Element), child(:bin, Bin)]
    )

    assert_pipeline_notified(pipeline, :element, :ready)
    Testing.Pipeline.execute_actions(pipeline, remove_children: :element)
    assert_receive :element_guard_triggered

    assert_pipeline_notified(pipeline, :bin, :ready)
    Testing.Pipeline.execute_actions(pipeline, remove_children: :bin)
    assert_receive :bin_guard_triggered

    Testing.Pipeline.execute_actions(pipeline,
      spec: [child(:element2, Element), child(:bin2, Bin)]
    )

    assert_pipeline_notified(pipeline, :element2, :ready)
    assert_pipeline_notified(pipeline, :bin2, :ready)
    assert :ready = Membrane.Pipeline.call(pipeline, :setup_guard)
    Membrane.Pipeline.terminate(pipeline)
    assert_receive :element_guard_triggered
    assert_receive :bin_guard_triggered
    assert_receive :pipeline_guard_triggered
  end

  test "Resources can be cleaned up manually and automatically when the owner process dies" do
    test_pid = self()

    {:ok, task} =
      Task.start_link(fn ->
        {:ok, guard} = ResourceGuard.start_link()

        ResourceGuard.register(guard, fn -> send(test_pid, :cleanup) end, tag: :tag)
        ResourceGuard.register(guard, fn -> send(test_pid, :cleanup2) end, tag: :tag)
        ResourceGuard.register(guard, fn -> send(test_pid, :cleanup3) end, tag: :other_tag)
        resource_tag = ResourceGuard.register(guard, fn -> send(test_pid, :cleanup4) end)
        ResourceGuard.cleanup(guard, :tag)
        ResourceGuard.unregister(guard, resource_tag)

        receive do: (:exit -> :ok)
      end)

    assert_receive message
    assert message == :cleanup2
    assert_receive message
    assert message == :cleanup
    refute_receive :cleanup3
    send(task, :exit)
    refute_receive :cleanup
    refute_receive :cleanup2
    assert_receive :cleanup3
    refute_receive :cleanup4
  end
end
