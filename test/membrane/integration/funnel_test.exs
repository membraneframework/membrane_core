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

  @tag :vibe_coded
  test "Sends NewInputEvent when an input is linked while playing" do
    import Membrane.ChildrenSpec

    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec:
          child(:src1, %Testing.Source{output: 1..10})
          |> child(:funnel, %Funnel{end_of_stream: :never})
          |> child(:sink, Testing.Sink)
      )

    Enum.each(1..10, fn payload ->
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: ^payload})
    end)

    refute_sink_event(pipeline, :sink, %Funnel.NewInputEvent{}, 0)

    Testing.Pipeline.execute_actions(pipeline,
      spec: child(:src2, %Testing.Source{output: 11..20}) |> get_child(:funnel)
    )

    assert_sink_event(pipeline, :sink, %Funnel.NewInputEvent{})

    Enum.each(11..20, fn payload ->
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: ^payload})
    end)

    Testing.Pipeline.terminate(pipeline)
  end
end
