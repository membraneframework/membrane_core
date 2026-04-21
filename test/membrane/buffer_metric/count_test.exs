defmodule Membrane.Core.Element.ManualFlowController.BufferMetric.CountTest do
  use ExUnit.Case, async: true

  alias Membrane.Buffer
  alias Membrane.Core.Element.ManualFlowController.BufferMetric

  @unit :buffers

  @buf1 %Buffer{payload: :pay1}
  @buf2 %Buffer{payload: :pay2}
  @buffers [@buf1, @buf2]
  @count 1

  describe ".buffers_size/2" do
    test "should return count of all buffers" do
      assert BufferMetric.buffers_size(@unit, @buffers) == {:ok, 2}
    end
  end

  describe ".split_buffers/6" do
    test "should return split buffers" do
      {extracted, rest} = BufferMetric.split_buffers(@unit, @buffers, @count, nil, nil, nil)

      assert extracted == [@buf1]
      assert rest == [@buf2]
    end
  end

  test ".reduce_demand/3 should subtract the consumed count from the remaining demand" do
    assert BufferMetric.reduce_demand(@unit, 10, 3) == 7
  end
end
