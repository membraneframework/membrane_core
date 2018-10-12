defmodule Membrane.Integration.DemandsTest do
  use ExUnit.Case, async: false
  use Bunch
  alias Membrane.Integration.{TestingFilter, TestingSource, TestingSink, TestingPipeline}
  alias Membrane.Pipeline

  def test_pipeline(pid) do
    pattern_gen = fn i -> <<i :: 16>> <> <<255>> end
    assert Pipeline.play(pid) == :ok
    assert_receive :playing, 2000
    demand = 500
    send(pid, {:child_msg, :sink, {:make_demand, demand}})

    0..(demand - 1)
    |> Enum.each(fn i ->
      pattern = pattern_gen.(i)
      assert_receive ^pattern
    end)

    pattern = pattern_gen.(demand)
    refute_receive ^pattern
    send(pid, {:child_msg, :sink, {:make_demand, demand}})

    demand..(2 * demand - 1)
    |> Enum.each(fn i ->
      pattern = pattern_gen.(i)
      assert_receive ^pattern
    end)
    assert Pipeline.stop(pid) == :ok
  end

  test "Regular pipeline with proper demands" do
    assert {:ok, pid} =
             Pipeline.start_link(TestingPipeline, %{
               source: TestingSource,
               filter: TestingFilter,
               sink: %TestingSink{target: self()},
               target: self()
             })

    test_pipeline(pid)
  end

  test "Pipeline with filter underestimating demand" do
    filter_demand_gen = fn _ -> 2 end

    assert {:ok, pid} =
             Pipeline.start_link(TestingPipeline, %{
               source: TestingSource,
               filter: %TestingFilter{demand_generator: filter_demand_gen},
               sink: %TestingSink{target: self()},
               target: self()
             })

    test_pipeline(pid)
  end

  test "Pipeline with source not generating enough buffers" do
    alias Membrane.Buffer

    actions_gen =
      fn cnt, _size ->
        cnt..(4 + cnt - 1)
        |> Enum.map(fn cnt ->
          buf = %Buffer{payload: <<cnt :: 16>>}

          {:buffer, {:output, buf}}
        end)
        |> Enum.concat([redemand: :output])
        ~> {&1, cnt + 4}
      end

    assert {:ok, pid} =
             Pipeline.start_link(TestingPipeline, %{
               source: %TestingSource{actions_generator: actions_gen},
               filter: TestingFilter,
               sink: %TestingSink{target: self()},
               target: self()
             })

    test_pipeline(pid)
  end
end
