defmodule Membrane.BufferSpec do
  use ESpec, async: true

  describe "when creating new struct" do
    it "should have payload field set to nil" do
      %Membrane.Buffer{payload: payload} = struct(described_module())
      expect(payload).to be_nil()
    end

    it "should have metadata field set to empty Metadata structure" do
      %Membrane.Buffer{metadata: metadata} = struct(described_module())
      expect(metadata).to eq Membrane.Buffer.Metadata.new()
    end
  end
end
