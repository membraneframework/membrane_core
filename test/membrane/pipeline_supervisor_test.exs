defmodule Membrane.PipelineSupervisorTest do
  use ExUnit.Case

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
end
