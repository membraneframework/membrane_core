defmodule Membrane.Integration.DemandsTest do
  use ExUnit.Case, async: false
  alias Membrane.Integration.{TestingFilter, TestingSource, TestingSink, TestingPipeline}
  alias Membrane.Pipeline

  test "Regular pipeline with proper demands" do
    assert {:ok, pid} =
             Pipeline.start_link(TestingPipeline, %{
               source: TestingSource,
               filter: TestingFilter,
               sink: %TestingSink{target: self()},
               target: self()
             })

    assert Pipeline.play(pid) == :ok
    assert_receive :playing, 2000
    demand = 100
    send(pid, {:child_msg, :sink, {:make_demand, demand}})

    0..(demand - 1)
    |> Enum.each(fn i ->
      pattern = <<i>> <> <<255>>
      assert_receive ^pattern
    end)

    send(pid, {:child_msg, :sink, {:make_demand, demand}})

    demand..(2 * demand - 1)
    |> Enum.each(fn i ->
      pattern = <<i>> <> <<255>>
      assert_receive ^pattern
    end)
    assert Pipeline.stop(pid) == :ok
    :c.flush()
  end

  test "Pipeline with filter underestimating demand" do
    :c.flush()
    filter_demand_gen = fn _ -> 2 end

    assert {:ok, pid} =
             Pipeline.start_link(TestingPipeline, %{
               source: TestingSource,
               filter: %TestingFilter{demand_generator: filter_demand_gen},
               #filter: TestingFilter,
               sink: %TestingSink{target: self()},
               target: self()
             })

    assert Pipeline.play(pid) == :ok
    assert_receive :playing, 2000
    demand = 1000
    send(pid, {:child_msg, :sink, {:make_demand, demand}})

    0..(demand - 1)
    |> Enum.each(fn i ->
      pattern = <<i>> <> <<255>>
      assert_receive ^pattern, 2000
    end)

    send(pid, {:child_msg, :sink, {:make_demand, demand}})

    demand..(2 * demand - 1)
    |> Enum.each(fn i ->
      pattern = <<i>> <> <<255>>
      assert_receive ^pattern
    end)
  end
end
