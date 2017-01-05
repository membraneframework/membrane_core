defmodule Membrane.BufferSpec do
  use ESpec, async: true

  describe "when creating new struct" do
    it "should have caps field set to nil" do
      %Membrane.Buffer{caps: caps} = struct(described_module)
      expect(caps).to be_nil
    end

    it "should have payload field set to nil" do
      %Membrane.Buffer{payload: payload} = struct(described_module)
      expect(payload).to be_nil
    end
  end
end
