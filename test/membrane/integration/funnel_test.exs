defmodule Membrane.Integration.FunnelTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.{Buffer, Funnel, Testing}

  test "Collects multiple inputs" do
    import Membrane.ChildrenSpec
    data = 1..10

    {:ok, _supervisor_pid, pipeline} =
      Testing.Pipeline.start_link(
        spec: [
          child(:funnel, Funnel),
          child(:src1, %Testing.Source{output: data}) |> get_child(:funnel),
          child(:src2, %Testing.Source{output: data}) |> get_child(:funnel),
          get_child(:funnel) |> child(:sink, Testing.Sink)
        ]
      )

    data
    |> Enum.flat_map(&[&1, &1])
    |> Enum.each(fn payload ->
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: ^payload})
    end)

    assert_end_of_stream(pipeline, :sink)
    refute_sink_buffer(pipeline, :sink, _buffer, 0)

    Membrane.Pipeline.terminate(pipeline)
  end
end
