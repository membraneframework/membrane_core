defmodule Membrane.Element.StateSpec do
  use ESpec, async: true

  describe "when creating new struct" do
    it "should have internal_state field set to nil" do
      %Membrane.Element.State{internal_state: internal_state} = struct(described_module())
      expect(internal_state).to be_nil()
    end

    it "should have module field set to nil" do
      %Membrane.Element.State{module: module} = struct(described_module())
      expect(module).to be_nil()
    end

    it "should have playback_state field set to :stopped" do
      %Membrane.Element.State{playback_state: playback_state} = struct(described_module())
      expect(playback_state).to eq :stopped
    end

    it "should have source_pads field set to an empty map" do
      %Membrane.Element.State{source_pads: source_pads} = struct(described_module())
      expect(source_pads).to eq %{}
    end

    it "should have sink_pads field set to an empty map" do
      %Membrane.Element.State{sink_pads: sink_pads} = struct(described_module())
      expect(sink_pads).to eq %{}
    end

    it "should have message_bus field set to nil" do
      %Membrane.Element.State{message_bus: message_bus} = struct(described_module())
      expect(message_bus).to be_nil()
    end
  end
end
