defmodule Membrane.Buffer.Metric.CountTest do
  use ExUnit.Case, async: true
  alias Membrane.Buffer
  alias Membrane.Buffer.Metric.Count

  @buf1 %Buffer{payload: :pay1}
  @buf2 %Buffer{payload: :pay2}
  @buffers [@buf1, @buf2]
  @count 1

  describe ".buffers_size/1" do
    test "should return count of all buffers" do
      assert Count.buffers_size(@buffers) == 2
    end
  end

  describe ".split_buffers/2" do
    test "should return splitted buffers" do
      {extracted, rest} = Count.split_buffers(@buffers, @count)

      assert extracted == [@buf1]
      assert rest == [@buf2]
    end
  end
end
