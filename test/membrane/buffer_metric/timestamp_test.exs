defmodule Membrane.Core.Element.ManualFlowController.BufferMetric.TimestampTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Membrane.Buffer
  alias Membrane.Core.Element.ManualFlowController.BufferMetric

  @t0 0 |> Membrane.Time.milliseconds()
  @t1 100 |> Membrane.Time.milliseconds()
  @t2 250 |> Membrane.Time.milliseconds()
  @t3 350 |> Membrane.Time.milliseconds()
  @t4 500 |> Membrane.Time.milliseconds()

  @demand 300 |> Membrane.Time.milliseconds()

  @pts_unit {:timestamp, :pts}
  @dts_unit {:timestamp, :dts}
  @dts_or_pts_unit {:timestamp, :dts_or_pts}

  defp buf(ts_field, ts), do: struct(%Buffer{payload: <<>>}, [{ts_field, ts}])

  test ".init_manual_demand_size/1 returns -1 as the no-demand sentinel" do
    assert BufferMetric.init_manual_demand_size(@pts_unit) == -1
    assert BufferMetric.init_manual_demand_size(@dts_unit) == -1
    assert BufferMetric.init_manual_demand_size(@dts_or_pts_unit) == -1
  end

  test ".reduce_demand/3 always returns the demand unchanged regardless of consumed size" do
    for unit <- [@pts_unit, @dts_unit, @dts_or_pts_unit] do
      assert BufferMetric.reduce_demand(unit, 1_000, 5) == 1_000
      assert BufferMetric.reduce_demand(unit, 1_000, nil) == 1_000
    end
  end

  test ".buffers_size/2 returns {:error, :operation_not_supported}" do
    for unit <- [@pts_unit, @dts_unit, @dts_or_pts_unit] do
      assert BufferMetric.buffers_size(unit, []) == {:error, :operation_not_supported}

      assert BufferMetric.buffers_size(unit, [%Buffer{payload: <<>>}]) ==
               {:error, :operation_not_supported}
    end
  end

  describe ".split_buffers/5" do
    for {unit, name, ts_field} <- [
          {{:timestamp, :pts}, "PTS", :pts},
          {{:timestamp, :dts}, "DTS", :dts}
        ] do
      test "returns {[], buffers} when demand is the initial sentinel value (-1) for #{name}" do
        buffers = Enum.map([@t0, @t1, @t2], &buf(unquote(ts_field), &1))
        assert BufferMetric.split_buffers(unquote(unit), buffers, -1, nil, nil) == {[], buffers}
      end

      test "uses first buffer's #{name} as offset when no buffers have been consumed yet" do
        buffers = Enum.map([@t0, @t1, @t2, @t3, @t4], &buf(unquote(ts_field), &1))

        {consumed, remaining} =
          BufferMetric.split_buffers(unquote(unit), buffers, @demand, nil, nil)

        assert Enum.map(consumed, &Map.get(&1, unquote(ts_field))) == [@t0, @t1, @t2, @t3]
        assert Enum.map(remaining, &Map.get(&1, unquote(ts_field))) == [@t4]
      end

      test "uses first_consumed_buffer's #{name} as offset when buffers have been consumed" do
        buffers = Enum.map([@t0, @t1, @t2, @t3, @t4], &buf(unquote(ts_field), &1))
        first_consumed = buf(unquote(ts_field), @t0)
        last_consumed = buf(unquote(ts_field), @t1)

        {consumed, remaining} =
          BufferMetric.split_buffers(
            unquote(unit),
            buffers,
            @demand,
            first_consumed,
            last_consumed
          )

        assert Enum.map(consumed, &Map.get(&1, unquote(ts_field))) == [@t0, @t1, @t2, @t3]
        assert Enum.map(remaining, &Map.get(&1, unquote(ts_field))) == [@t4]
      end

      test "returns all buffers for #{name} when demand exceeds the available timestamp range" do
        buffers = Enum.map([@t0, @t1, @t2, @t3, @t4], &buf(unquote(ts_field), &1))

        {consumed, remaining} =
          BufferMetric.split_buffers(unquote(unit), buffers, @t4 * 10, nil, nil)

        assert consumed == buffers
        assert remaining == []
      end

      test "emits a warning and returns {[], buffers} for #{name} when elapsed duration already meets demand" do
        buffers = Enum.map([@t0, @t1, @t2, @t3, @t4], &buf(unquote(ts_field), &1))
        first_consumed = buf(unquote(ts_field), @t0)
        last_consumed = buf(unquote(ts_field), @t4)

        log =
          capture_log(fn ->
            assert BufferMetric.split_buffers(
                     unquote(unit),
                     buffers,
                     @demand,
                     first_consumed,
                     last_consumed
                   ) ==
                     {[], buffers}
          end)

        assert log =~ "warning"
        assert log =~ unquote(name)
      end
    end

    test "DTSorPTS prefers DTS when present, falls back to PTS" do
      buf_with_dts = %Buffer{payload: <<>>, dts: @t0, pts: @t4}
      buf_pts_only = %Buffer{payload: <<>>, pts: @t3}

      {consumed, remaining} =
        BufferMetric.split_buffers(
          @dts_or_pts_unit,
          [buf_with_dts, buf_pts_only],
          @demand,
          nil,
          nil
        )

      assert consumed == [buf_with_dts, buf_pts_only]
      assert remaining == []
    end

    test "returns {[], []} when buffers is empty and no buffers have been consumed yet" do
      for unit <- [@pts_unit, @dts_unit, @dts_or_pts_unit] do
        assert BufferMetric.split_buffers(unit, [], @demand, nil, nil) == {[], []}
      end
    end

    test "DTSorPTS uses first buffer's DTS-or-PTS as offset when no buffers have been consumed yet" do
      buffers = Enum.map([@t0, @t1, @t2, @t3, @t4], &%Buffer{payload: <<>>, dts: &1})

      {consumed, remaining} =
        BufferMetric.split_buffers(@dts_or_pts_unit, buffers, @demand, nil, nil)

      assert Enum.map(consumed, & &1.dts) == [@t0, @t1, @t2, @t3]
      assert Enum.map(remaining, & &1.dts) == [@t4]
    end
  end

  describe ".generate_metric_specific_warnings/3" do
    test "returns :ok for an empty list" do
      assert BufferMetric.generate_metric_specific_warnings(nil, [], @pts_unit) == :ok
      assert BufferMetric.generate_metric_specific_warnings(nil, [], @dts_unit) == :ok
      assert BufferMetric.generate_metric_specific_warnings(nil, [], @dts_or_pts_unit) == :ok
    end

    for {unit, name, ts_field} <- [
          {{:timestamp, :pts}, "PTS", :pts},
          {{:timestamp, :dts}, "DTS", :dts}
        ] do
      test "emits no warning for monotonically increasing #{name}s" do
        buffers = Enum.map([@t0, @t1, @t2, @t3], &buf(unquote(ts_field), &1))

        log =
          capture_log(fn ->
            assert BufferMetric.generate_metric_specific_warnings(nil, buffers, unquote(unit)) ==
                     :ok
          end)

        refute log =~ "warning"
      end

      test "emits a warning for non-monotonic #{name}s" do
        buffers = Enum.map([@t0, @t3, @t1, @t4], &buf(unquote(ts_field), &1))

        log =
          capture_log(fn ->
            assert BufferMetric.generate_metric_specific_warnings(nil, buffers, unquote(unit)) ==
                     :ok
          end)

        assert log =~ "warning"
        assert log =~ unquote(name)
      end
    end

    test "DTSorPTS emits a warning for non-monotonic DTS-or-PTS values" do
      buffers = Enum.map([@t0, @t3, @t1, @t4], &%Buffer{payload: <<>>, dts: &1})

      log =
        capture_log(fn ->
          assert BufferMetric.generate_metric_specific_warnings(nil, buffers, @dts_or_pts_unit) ==
                   :ok
        end)

      assert log =~ "warning"
      assert log =~ "<DTS || PTS>"
    end
  end
end
