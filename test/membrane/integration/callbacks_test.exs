defmodule Membrane.Integration.CallbacksTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.Testing

  defmodule PadlessElement do
    use Membrane.Endpoint
  end

  defmodule PadlessElementPipeline do
    use Membrane.Pipeline
    alias Membrane.Integration.CallbacksTest.PadlessElement

    @impl true
    def handle_child_terminated(child_name, ctx, state) do
      assert not is_map_key(ctx.children, child_name)
      {[spec: child(child_name, PadlessElement)], state}
    end
  end

  test "handle_child_terminated" do
    pipeline = Testing.Pipeline.start_link_supervised!(module: PadlessElementPipeline)

    Testing.Pipeline.execute_actions(pipeline, spec: child(:element, PadlessElement))
    first_pid = Testing.Pipeline.get_child_pid!(pipeline, :element)
    refute_child_terminated(pipeline, :element, 500)

    Testing.Pipeline.execute_actions(pipeline, remove_children: :element)
    assert_child_terminated(pipeline, :element)
    second_pid = Testing.Pipeline.get_child_pid!(pipeline, :element)

    assert first_pid != second_pid

    Testing.Pipeline.terminate(pipeline)
  end
end
