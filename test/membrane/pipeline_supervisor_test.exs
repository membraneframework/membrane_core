defmodule Membrane.PipelineSupervisorTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  test "Pipeline supervisor exits with the same reason as pipeline" do
    defmodule MyPipeline do
      use Membrane.Pipeline
    end

    {:ok, supervisor, pipeline} = Membrane.Pipeline.start(MyPipeline)

    supervisor_monitor_ref = Process.monitor(supervisor)
    pipeline_monitor_ref = Process.monitor(pipeline)

    exit_reason = :custom_exit_reason
    Process.exit(pipeline, exit_reason)

    assert_receive {:DOWN, ^pipeline_monitor_ref, _process, _pid, ^exit_reason}
    assert_receive {:DOWN, ^supervisor_monitor_ref, _process, _pid, ^exit_reason}
  end

  test "Pipeline supervisor exits with {:membrane_child_crash, child_name} when pipeline's child crashes" do
    defmodule MyElement do
      use Membrane.Endpoint

      @impl true
      def handle_playing(_ctx, state) do
        {[notify_parent: {:element_pid, self()}], state}
      end
    end

    {:ok, supervisor, pipeline} = Testing.Pipeline.start(spec: child(:element, MyElement))

    assert_pipeline_notified(pipeline, :element, {:element_pid, element})

    supervisor_monitor_ref = Process.monitor(supervisor)
    pipeline_monitor_ref = Process.monitor(pipeline)
    element_monitor_ref = Process.monitor(element)

    element_exit_reason = :custom_exit_reason
    Process.exit(element, element_exit_reason)

    pipeline_exit_reason = {:membrane_child_crash, :element}

    assert_receive {:DOWN, ^element_monitor_ref, _process, _pid, ^element_exit_reason}
    assert_receive {:DOWN, ^pipeline_monitor_ref, _process, _pid, ^pipeline_exit_reason}
    assert_receive {:DOWN, ^supervisor_monitor_ref, _process, _pid, ^pipeline_exit_reason}
  end
end
