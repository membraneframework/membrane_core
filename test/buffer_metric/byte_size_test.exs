defmodule Membrane.Buffer.Metric.ByteSizeTest do
  use ExUnit.Case, async: true
  alias Membrane.Buffer
  alias Membrane.Buffer.Metric.ByteSize

  @pay1 <<0, 1, 2, 3, 4, 5>>
  @pay2 <<6, 7, 8, 9, 10, 11>>
  @buf1 %Buffer{payload: @pay1}
  @buf2 %Buffer{payload: @pay2}
  @single_buffer [@buf1]
  @buffers [@buf1, @buf2]

  describe ".buffers_size/1" do
    test "should return size of all buffers" do
      size = ByteSize.buffers_size(@buffers)
      assert size == byte_size(@pay1) + byte_size(@pay2)
    end
  end

  describe ".split_buffers/2" do
    test "when split position matches size of first buffer, extract only first buffer" do
      {buf, rest} = ByteSize.split_buffers(@buffers, byte_size(@pay1))
      assert buf == [@buf1]
      assert rest == [@buf2]
    end

    test "when there is only one buffer where split position is greater than buffer size \
      returns the buffer and an empty list" do
      {buf, []} = ByteSize.split_buffers(@single_buffer, byte_size(@pay1) + 10)
      assert buf == [@buf1]
    end

    test "when there is only one buffer where split position is 0, it returns an empty \
      list and a list with the buffer" do
      {[], rest} = ByteSize.split_buffers(@single_buffer, 0)
      assert rest == [@buf1]
    end

    test "when splitting buffer is necessary extracts first buffer and create separate \
      buffer for the first part of the second buffer" do
      {extracted, _} = ByteSize.split_buffers(@buffers, byte_size(@pay1) + 1)
      <<one_byte::binary-size(1), _::binary>> = @pay2
      assert extracted == [@buf1, %Membrane.Buffer{payload: one_byte}]
    end

    test "when splitting buffer is necessary return the second part of the second buffer" do
      {_, rest} = ByteSize.split_buffers(@buffers, byte_size(@pay1) + 1)
      <<_::binary-size(1), expected_pay::binary>> = @pay2
      assert rest == [%Membrane.Buffer{payload: expected_pay}]
    end
  end
end
