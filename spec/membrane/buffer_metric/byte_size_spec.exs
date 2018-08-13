defmodule Membrane.Buffer.Metric.ByteSizeSpec do
  use ESpec, async: true
  alias Membrane.Buffer

  let :pay1, do: <<0, 1, 2, 3, 4, 5>>
  let :pay2, do: <<6, 7, 8, 9, 10, 11>>
  let :buf1, do: %Buffer{payload: pay1()}
  let :buf2, do: %Buffer{payload: pay2()}
  let :buffers, do: [buf1(), buf2()]

  describe ".buffers_size/1" do
    it "should return size of all buffers" do
      size = described_module().buffers_size(buffers())
      expect(size) |> to(eq byte_size(pay1()) + byte_size(pay2()))
    end
  end

  describe ".split_buffers/2" do
    context "when split position matches size of first buffer" do
      let :count, do: byte_size(pay1())

      it "should extract only first buffer" do
        {buf, rest} = described_module().split_buffers(buffers(), count())
        expect(buf) |> to(eq [buf1()])
        expect(rest) |> to(eq [buf2()])
      end
    end

    context "when there is only one buffer" do
      let :buffers, do: [buf1()]

      context "and split position is greater than buffer size" do
        it "should return a list with the buffer and an empty one" do
          {buf, rest} = described_module().split_buffers(buffers(), byte_size(pay1()) + 10)
          expect(buf) |> to(eq [buf1()])
          expect(rest) |> to(eq [])
        end
      end

      context "and split position is 0" do
        it "should return an empty list and a list with the buffer" do
          {buf, rest} = described_module().split_buffers(buffers(), 0)
          expect(buf) |> to(eq [])
          expect(rest) |> to(eq [buf1()])
        end
      end
    end

    context "when splitting buffer is necessary" do
      let :count, do: byte_size(pay1()) + 1

      it "should return extract first buffer and create separate buffer for the next byte from the second buffer" do
        {extracted, _} = described_module().split_buffers(buffers(), count())
        <<one_byte::binary-size(1), _::binary>> = pay2()
        expect(extracted) |> to(eq [buf1(), %Membrane.Buffer{payload: one_byte}])
      end

      it "should return second buffer without first byte" do
        {_, rest} = described_module().split_buffers(buffers(), count())
        <<_::binary-size(1), expected_pay::binary>> = pay2()
        expect(rest) |> to(eq [%Membrane.Buffer{payload: expected_pay}])
      end
    end
  end
end
