defmodule Membrane.TimeTest do
  use ExUnit.Case, async: true

  @module Membrane.Time

  # Apr 20, 2020 11:23:52.178157999
  @ntp_timestamp <<3_796_370_632::32, 765_182_783::32>>
  @timestamp_unix_ns 1_587_381_832_178_157_999

  doctest @module

  test "conversion from NTP" do
    timestamp = @ntp_timestamp |> @module.from_ntp_timestamp()
    assert_in_delta timestamp, @timestamp_unix_ns, 1
  end

  test "conversion to NTP " do
    unix_timestamp = @timestamp_unix_ns |> @module.nanoseconds()
    assert <<seconds::32, fraction::32>> = unix_timestamp |> @module.to_ntp_timestamp()

    <<ref_seconds::32, ref_fraction::32>> = @ntp_timestamp
    assert seconds == ref_seconds
    # 10 decimal means 10 / 2^32 delta, that is ~ 2.33 nanoseconds
    assert_in_delta fraction, ref_fraction, 10
  end

  test "NTP convesion error " do
    regenerated_timestamp =
      @timestamp_unix_ns |> @module.to_ntp_timestamp() |> @module.from_ntp_timestamp()

    assert_in_delta @timestamp_unix_ns, regenerated_timestamp, 1
  end

  test "Time units" do
    value = 123
    assert @module.nanoseconds(value) == value
    assert @module.microseconds(value) == value * 1000
    assert @module.milliseconds(value) == value * 1_000_000
    assert @module.seconds(value) == value * 1_000_000_000
    assert @module.hours(value) == value * 3_600_000_000_000
    assert @module.days(value) == value * 86_400_000_000_000

    assert value |> @module.seconds() |> @module.native_units() ==
             :erlang.convert_time_unit(value, :seconds, :native)
  end

  test "Monotonic time should be integer" do
    assert is_integer(@module.monotonic_time())
  end

  test "Time units functions work properly with rational numbers" do
    value = Ratio.new(1, 2)
    assert @module.microseconds(value) == 500
    assert @module.milliseconds(value) == 500_000
    assert @module.seconds(value) == 500_000_000
    assert @module.hours(value) == 1_800_000_000_000
    assert @module.days(value) == 43_200_000_000_000
  end

  test "Time units functions properly round the values" do
    assert @module.seconds(Ratio.new(1, 3)) == 333_333_333
    assert @module.seconds(Ratio.new(-1, 3)) == -333_333_333

    assert @module.seconds(Ratio.new(2, 3)) == 666_666_667
    assert @module.seconds(Ratio.new(-2, 3)) == -666_666_667
  end

  test "Time.to_timebase/2 works properly" do
    assert @module.divide_by_timebase(4, 2) == 2
    assert @module.divide_by_timebase(3, Ratio.new(3, 2)) == 2
    assert @module.divide_by_timebase(Ratio.new(15, 2), 2) == 4
    assert @module.divide_by_timebase(Ratio.new(15, 2), Ratio.new(3, 2)) == 5
    assert @module.divide_by_timebase(4, 10) == 0
    assert @module.divide_by_timebase(4, 7) == 1
  end
end
