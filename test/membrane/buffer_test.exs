defmodule Membrane.BufferTest do
  use ExUnit.Case, async: true

  alias Membrane.Buffer

  describe "Buffer.get_dts_or_pts" do
    test "returns dts when both dts and pts are set" do
      buffer = %Buffer{payload: <<>>, dts: 1, pts: 0}
      assert Buffer.get_dts_or_pts(buffer) == 1
    end

    test "returns pts when only pts is set" do
      buffer = %Buffer{payload: <<>>, pts: 1}
      assert Buffer.get_dts_or_pts(buffer) == 1
    end

    test "returns dts when only dts is set" do
      buffer = %Buffer{payload: <<>>, dts: 1}
      assert Buffer.get_dts_or_pts(buffer) == 1
    end

    test "returns nil when both dts and pts are not set" do
      buffer = %Buffer{payload: <<>>}
      assert Buffer.get_dts_or_pts(buffer) == nil
    end
  end
end
