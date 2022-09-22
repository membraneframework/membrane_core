defmodule Membrane.Integration.ChildSpawnTest do
  use Bunch
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions

  alias Membrane.Core.Message
  alias Membrane.ParentSpec
  alias Membrane.Testing


  require Message

  test "if  to/3 don't spawn child with a given name if there is already a child with given name among the children" do
    import ParentSpec

    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(structure: spawn_child(:sink, Testing.Sink))

    structure = [
      spawn_child(:source, %Testing.Source{output: [1, 2, 3]}) |> to_new(:sink, Testing.Sink)
    ]

    spec = %ParentSpec{structure: structure}
    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec, playback: :playing)
    assert_pipeline_play(pipeline_pid)
  end

  test "if  to/3 spawns a new child with a given name if there is no child with given name among the children" do
    import ParentSpec

    pipeline_pid = Testing.Pipeline.start_link_supervised!(structure: [])

    structure = [
      spawn_child(:source, %Testing.Source{output: [1, 2, 3]}) |>  to_new(:sink, Testing.Sink)
    ]

    spec = %ParentSpec{structure: structure}
    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec, playback: :playing)
    assert_pipeline_play(pipeline_pid)
  end
end
