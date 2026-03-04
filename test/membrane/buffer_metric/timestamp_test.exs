defmodule Membrane.Buffer.Metric.TimestampTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Membrane.Buffer
  alias Membrane.Buffer.Metric.Timestamp.{DTS, DTSOrPTS, PTS}

  @t0 0 |> Membrane.Time.milliseconds()
  @t1 100 |> Membrane.Time.milliseconds()
  @t2 250 |> Membrane.Time.milliseconds()
  @t3 350 |> Membrane.Time.milliseconds()
  @t4 500 |> Membrane.Time.milliseconds()

  @demand 300 |> Membrane.Time.milliseconds()

  defp buf(ts_field, ts), do: struct(%Buffer{payload: <<>>}, [{ts_field, ts}])

  test ".init_manual_demand_size_value/0 returns -1 as the no-demand sentinel" do
    assert PTS.init_manual_demand_size_value() == -1
    assert DTS.init_manual_demand_size_value() == -1
    assert DTSOrPTS.init_manual_demand_size_value() == -1
  end

  test ".reduce_demand/2 always returns the demand unchanged regardless of consumed size" do
    for module <- [PTS, DTS, DTSOrPTS] do
      assert module.reduce_demand(1_000, 5) == 1_000
      assert module.reduce_demand(1_000, nil) == 1_000
    end
  end

  test ".buffers_size/1 returns {:error, :operation_not_supported}" do
    for module <- [PTS, DTS, DTSOrPTS] do
      assert module.buffers_size([]) == {:error, :operation_not_supported}
      assert module.buffers_size([%Buffer{payload: <<>>}]) == {:error, :operation_not_supported}
    end
  end

  describe ".split_buffers/4" do
    for {module, name, ts_field} <- [{PTS, "PTS", :pts}, {DTS, "DTS", :dts}] do
      test "returns {[], buffers} when demand is the initial sentinel value (-1) for #{name}" do
        buffers = Enum.map([@t0, @t1, @t2], &buf(unquote(ts_field), &1))
        assert unquote(module).split_buffers(buffers, -1, nil, nil) == {[], buffers}
      end

      test "uses first buffer's #{name} as offset when no buffers have been consumed yet" do
        buffers = Enum.map([@t0, @t1, @t2, @t3, @t4], &buf(unquote(ts_field), &1))

        {consumed, remaining} = unquote(module).split_buffers(buffers, @demand, nil, nil)
        assert Enum.map(consumed, &Map.get(&1, unquote(ts_field))) == [@t0, @t1, @t2, @t3]
        assert Enum.map(remaining, &Map.get(&1, unquote(ts_field))) == [@t4]
      end

      test "uses first_consumed_buffer's #{name} as offset when buffers have been consumed" do
        buffers = Enum.map([@t0, @t1, @t2, @t3, @t4], &buf(unquote(ts_field), &1))
        # first_consumed at @t0 → same offset as above, same split point
        first_consumed = buf(unquote(ts_field), @t0)
        last_consumed = buf(unquote(ts_field), @t1)

        {consumed, remaining} =
          unquote(module).split_buffers(buffers, @demand, first_consumed, last_consumed)

        assert Enum.map(consumed, &Map.get(&1, unquote(ts_field))) == [@t0, @t1, @t2, @t3]
        assert Enum.map(remaining, &Map.get(&1, unquote(ts_field))) == [@t4]
      end

      test "returns all buffers for #{name} when demand exceeds the available timestamp range" do
        buffers = Enum.map([@t0, @t1, @t2, @t3, @t4], &buf(unquote(ts_field), &1))
        {consumed, remaining} = unquote(module).split_buffers(buffers, @t4 * 10, nil, nil)
        assert consumed == buffers
        assert remaining == []
      end

      test "emits a warning and returns {[], buffers} for #{name} when elapsed duration already meets demand" do
        buffers = Enum.map([@t0, @t1, @t2, @t3, @t4], &buf(unquote(ts_field), &1))
        first_consumed = buf(unquote(ts_field), @t0)
        last_consumed = buf(unquote(ts_field), @t4)

        log =
          capture_log(fn ->
            assert unquote(module).split_buffers(buffers, @demand, first_consumed, last_consumed) ==
                     {[], buffers}
          end)

        assert log =~ "warning"
        assert log =~ unquote(name)
      end
    end

    test "DTSOrPTS prefers DTS when present, falls back to PTS" do
      # first buffer has dts=@t0 and pts=@t4: metric should use dts
      buf_with_dts = %Buffer{payload: <<>>, dts: @t0, pts: @t4}
      buf_pts_only = %Buffer{payload: <<>>, pts: @t3}

      {consumed, remaining} =
        DTSOrPTS.split_buffers([buf_with_dts, buf_pts_only], @demand, nil, nil)

      assert consumed == [buf_with_dts, buf_pts_only]
      assert remaining == []
    end
  end

  describe ".generate_metric_specific_warnings/1" do
    test "returns :ok for an empty list" do
      assert PTS.generate_metric_specific_warnings([]) == :ok
      assert DTS.generate_metric_specific_warnings([]) == :ok
      assert DTSOrPTS.generate_metric_specific_warnings([]) == :ok
    end

    for {module, name, ts_field} <- [{PTS, "PTS", :pts}, {DTS, "DTS", :dts}] do
      test "emits no warning for monotonically increasing #{name}s" do
        buffers = Enum.map([@t0, @t1, @t2, @t3], &buf(unquote(ts_field), &1))

        log =
          capture_log(fn ->
            assert unquote(module).generate_metric_specific_warnings(buffers) == :ok
          end)

        assert log == ""
      end

      test "emits a warning for non-monotonic #{name}s" do
        buffers = Enum.map([@t0, @t3, @t1, @t4], &buf(unquote(ts_field), &1))

        log =
          capture_log(fn ->
            assert unquote(module).generate_metric_specific_warnings(buffers) == :ok
          end)

        assert log =~ "warning"
        assert log =~ unquote(name)
      end
    end

    test "DTSOrPTS emits a warning for non-monotonic DTS-or-PTS values" do
      buffers = Enum.map([@t0, @t3, @t1, @t4], &%Buffer{payload: <<>>, dts: &1})

      log =
        capture_log(fn ->
          assert DTSOrPTS.generate_metric_specific_warnings(buffers) == :ok
        end)

      assert log =~ "warning"
      assert log =~ "DTS or PTS"
    end
  end
end
