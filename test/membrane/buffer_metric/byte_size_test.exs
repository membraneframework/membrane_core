defmodule Membrane.Core.Element.ManualFlowController.BufferMetric.ByteSizeTest do
  use ExUnit.Case, async: true

  alias Membrane.Buffer
  alias Membrane.Core.Element.ManualFlowController.BufferMetric

  @unit :bytes

  @pay1 <<0, 1, 2, 3, 4, 5>>
  @pay2 <<6, 7, 8, 9, 10, 11>>
  @buf1 %Buffer{payload: @pay1}
  @buf2 %Buffer{payload: @pay2}
  @single_buffer [@buf1]
  @buffers [@buf1, @buf2]

  describe ".buffers_size/2" do
    test "should return size of all buffers" do
      assert BufferMetric.buffers_size(@unit, @buffers) ==
               {:ok, byte_size(@pay1) + byte_size(@pay2)}
    end
  end

  describe ".split_buffers/6" do
    test "when split position matches size of first buffer, extract only first buffer" do
      {buf, rest} = BufferMetric.split_buffers(@unit, @buffers, byte_size(@pay1), nil, nil, nil)
      assert buf == [@buf1]
      assert rest == [@buf2]
    end

    test "when there is only one buffer where split position is greater than buffer size \
      returns the buffer and an empty list" do
      {buf, []} =
        BufferMetric.split_buffers(@unit, @single_buffer, byte_size(@pay1) + 10, nil, nil, nil)

      assert buf == [@buf1]
    end

    test "when there is only one buffer where split position is 0, it returns an empty \
      list and a list with the buffer" do
      {[], rest} = BufferMetric.split_buffers(@unit, @single_buffer, 0, nil, nil, nil)
      assert rest == [@buf1]
    end

    test "when splitting is necessary it extracts the first buffer and splits the second into two" do
      {extracted, rest} =
        BufferMetric.split_buffers(@unit, @buffers, byte_size(@pay1) + 1, nil, nil, nil)

      <<one_byte::binary-size(1), expected_rest::binary>> = @pay2
      assert extracted == [@buf1, %Membrane.Buffer{payload: one_byte}]
      assert rest == [%Membrane.Buffer{payload: expected_rest}]
    end
  end

  test ".reduce_demand/3 should subtract the consumed byte count from the remaining demand" do
    assert BufferMetric.reduce_demand(@unit, 1000, 400) == 600
  end
end
