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
end
