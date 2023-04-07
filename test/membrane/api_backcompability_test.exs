defmodule Membrane.APIBackCompabilityTest do
  # this module tests if API in membrane_core v0.12 has no breaking changes comparing to api in v0.11
  use ExUnit.Case, async: true

  alias Membrane.Testing

  import Membrane.ChildrenSpec

  test "if action :remove_child works" do
    defmodule Filter do
      use Membrane.Filter
    end

    pipeline = Testing.Pipeline.start_link_supervised!(spec: child(:filter, Filter))
    Process.sleep(100)
    filter_pid = Testing.Pipeline.get_child_pid!(pipeline, :filter)
    monitor_ref = Process.monitor(filter_pid)
    Testing.Pipeline.execute_actions(pipeline, remove_child: :filter)

    assert_receive {:DOWN, ^monitor_ref, _process, _pid, :normal}

    Testing.Pipeline.terminate(pipeline)
  end
end
