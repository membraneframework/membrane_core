defmodule Membrane.UtilitySupervisorTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  test "Utility supervisor terminates utility when element exits" do
    Process.register(self(), :utility_supervisor_test_process)

    defmodule TestFilter do
      use Membrane.Filter

      @impl true
      def handle_setup(ctx, state) do
        Membrane.UtilitySupervisor.start_link_child(
          ctx.utility_supervisor,
          {Task,
           fn ->
             send(:utility_supervisor_test_process, {:task_pid, self()})
             Process.sleep(:infinity)
           end}
        )

        {[notify_parent: :setup], state}
      end
    end

    pipeline = Testing.Pipeline.start_supervised!(spec: [child(:filter, TestFilter)])

    assert_pipeline_notified(pipeline, :filter, :setup)
    assert_receive {:task_pid, task_pid}

    monitor_ref = Process.monitor(task_pid)

    Testing.Pipeline.terminate(pipeline)
    assert_receive {:DOWN, ^monitor_ref, :process, _pid, :shutdown}
  end
end
