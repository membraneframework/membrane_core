defmodule Membrane.Buffer.Metric.CountSpec do
  use ESpec, async: true
  alias Membrane.Buffer

  let :buf1, do: %Buffer{payload: :pay1}
  let :buf2, do: %Buffer{payload: :pay2}
  let :buffers, do: [buf1(), buf2()]

  describe ".buffers_size/1" do
    it "should return count of all buffers" do
      size = described_module().buffers_size(buffers())
      expect(size) |> to(eq 2)
    end
  end

  describe ".split_buffers/2" do
    let :count, do: 1

    it "should return splitted buffers" do
      {extracted, rest} = described_module().split_buffers(buffers(), count())
      expect(extracted) |> to(eq [buf1()])
      expect(rest) |> to(eq [buf2()])
    end
  end
end
