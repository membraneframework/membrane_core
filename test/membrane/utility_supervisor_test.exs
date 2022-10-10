defmodule Membrane.UtilitySupervisorTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Testing

  test "Utility supervisor terminates utility when element exits" do
    defmodule TestFilter do
      use Membrane.Filter

      @impl true
      def handle_setup(ctx, state) do
        Membrane.UtilitySupervisor.start_link_child(
          ctx.utility_supervisor,
          {Task,
           fn ->
             Process.register(self(), :utility_supervisor_test_task)
             Process.sleep(:infinity)
           end}
        )

        {{:ok, notify_parent: :setup}, state}
      end
    end

    pipeline = Testing.Pipeline.start_supervised!(children: [filter: TestFilter])
    assert_pipeline_notified(pipeline, :filter, :setup)
    monitor = Process.monitor(:utility_supervisor_test_task)
    Testing.Pipeline.terminate(pipeline)
    assert_receive {:DOWN, ^monitor, :process, _pid, :shutdown}
  end
end
