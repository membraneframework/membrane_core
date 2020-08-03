defmodule Membrane.Integration.DemandsTest do
  use Bunch
  use ExUnit.Case, async: false

  import ExUnit.Assertions
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Support.DemandsTest.Filter
  alias Membrane.Testing.{Pipeline, Sink, Source}

  defp assert_buffers_received(range, pid) do
    Enum.each(range, fn i ->
      assert_sink_buffer(pid, :sink, %Buffer{payload: <<^i::16>> <> <<255>>})
    end)
  end

  defp test_pipeline(pid) do
    pattern_gen = fn i -> %Buffer{payload: <<i::16>> <> <<255>>} end
    assert Pipeline.play(pid) == :ok

    assert_pipeline_playback_changed(pid, :prepared, :playing)

    demand = 500
    Pipeline.message_child(pid, :sink, {:make_demand, demand})

    0..(demand - 1)
    |> assert_buffers_received(pid)

    pattern = pattern_gen.(demand)
    refute_sink_buffer(pid, :sink, ^pattern, 0)
    Pipeline.message_child(pid, :sink, {:make_demand, demand})

    demand..(2 * demand - 1)
    |> assert_buffers_received(pid)

    assert Pipeline.stop(pid) == :ok
  end

  test "Regular pipeline with proper demands" do
    assert {:ok, pid} =
             Pipeline.start_link(%Pipeline.Options{
               elements: [
                 source: Source,
                 filter: Filter,
                 sink: %Sink{autodemand: false}
               ]
             })

    test_pipeline(pid)
  end

  test "Pipeline with filter underestimating demand" do
    filter_demand_gen = fn _incoming_demand -> 2 end

    assert {:ok, pid} =
             Pipeline.start_link(%Pipeline.Options{
               elements: [
                 source: Source,
                 filter: %Filter{demand_generator: filter_demand_gen},
                 sink: %Sink{autodemand: false}
               ]
             })

    test_pipeline(pid)
  end

  test "Pipeline with source not generating enough buffers" do
    alias Membrane.Buffer

    actions_gen = fn cnt, _size ->
      cnt..(4 + cnt - 1)
      |> Enum.map(fn cnt ->
        buf = %Buffer{payload: <<cnt::16>>}

        {:buffer, {:output, buf}}
      end)
      |> Enum.concat(redemand: :output)
      ~> {&1, cnt + 4}
    end

    assert {:ok, pid} =
             Pipeline.start_link(%Pipeline.Options{
               elements: [
                 source: %Source{output: {0, actions_gen}},
                 filter: Filter,
                 sink: %Sink{autodemand: false}
               ]
             })

    test_pipeline(pid)
  end
end
