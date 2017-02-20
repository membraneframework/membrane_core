defmodule Membrane.MessageSpec do
  use ESpec, async: true

  describe "when creating new struct" do
    it "should have type field set to nil" do
      %Membrane.Message{type: type} = struct(described_module())
      expect(type).to be_nil()
    end

    it "should have payload field set to nil" do
      %Membrane.Message{payload: payload} = struct(described_module())
      expect(payload).to be_nil()
    end
  end
end
