defmodule Membrane.ResourceGuardTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions

  alias Membrane.{ResourceGuard, Testing}

  test "Resources are freed upon component termination" do
    defmodule Element do
      use Membrane.Source

      alias Membrane.ResourceGuard

      @impl true
      def handle_setup(ctx, state) do
        {:ok, pid} =
          Task.start(fn ->
            Process.register(self(), :membrane_resource_guard_test_element_resource)
            Process.sleep(:infinity)
          end)

        ResourceGuard.register_resource(ctx.resource_guard, fn ->
          Process.exit(pid, :shutdown)
        end)

        {{:ok, notify_parent: :ready}, state}
      end
    end

    defmodule Bin do
      use Membrane.Bin

      alias Membrane.ResourceGuard

      @impl true
      def handle_setup(ctx, state) do
        {:ok, pid} =
          Task.start(fn ->
            Process.register(self(), :membrane_resource_guard_test_bin_resource)
            Process.sleep(:infinity)
          end)

        ResourceGuard.register_resource(ctx.resource_guard, fn ->
          Process.exit(pid, :shutdown)
        end)

        {{:ok, notify_parent: :ready}, state}
      end
    end

    defmodule Pipeline do
      use Membrane.Pipeline

      alias Membrane.ResourceGuard

      @impl true
      def handle_call(:setup_guard, ctx, state) do
        {:ok, pid} =
          Task.start(fn ->
            Process.register(self(), :membrane_resource_guard_test_pipeline_resource)
            Process.sleep(:infinity)
          end)

        ResourceGuard.register_resource(ctx.resource_guard, fn ->
          Process.exit(pid, :shutdown)
        end)

        {{:ok, reply: :ready}, state}
      end
    end

    pipeline = Testing.Pipeline.start_link_supervised!(module: Pipeline)

    Testing.Pipeline.execute_actions(pipeline,
      spec: %Membrane.ParentSpec{structure: [element: Element, bin: Bin]}
    )

    assert_pipeline_notified(pipeline, :element, :ready)
    monitor_ref = Process.monitor(:membrane_resource_guard_test_element_resource)
    Testing.Pipeline.execute_actions(pipeline, remove_child: :element)
    assert_receive {:DOWN, ^monitor_ref, :process, _pid, :shutdown}

    assert_pipeline_notified(pipeline, :bin, :ready)
    monitor_ref = Process.monitor(:membrane_resource_guard_test_bin_resource)
    Testing.Pipeline.execute_actions(pipeline, remove_child: :bin)
    assert_receive {:DOWN, ^monitor_ref, :process, _pid, :shutdown}

    assert :ready = Membrane.Pipeline.call(pipeline, :setup_guard)
    monitor_ref = Process.monitor(:membrane_resource_guard_test_pipeline_resource)
    Membrane.Pipeline.terminate(pipeline, blocking?: true)
    assert_receive {:DOWN, ^monitor_ref, :process, _pid, :shutdown}
  end

  test "Resources can be cleaned up manually and automatically when the owner process dies" do
    test_pid = self()

    {:ok, task} =
      Task.start_link(fn ->
        {:ok, guard} = ResourceGuard.start_link()
        ResourceGuard.register_resource(guard, fn -> send(test_pid, :cleanup) end, :resource)
        ResourceGuard.register_resource(guard, fn -> send(test_pid, :cleanup2) end, :resource)
        ResourceGuard.register_resource(guard, fn -> send(test_pid, :cleanup3) end, :other_name)
        ResourceGuard.cleanup_resource(guard, :resource)
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
  end
end