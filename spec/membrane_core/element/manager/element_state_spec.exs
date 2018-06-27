defmodule Membrane.Core.Element.StateSpec do
  use ESpec, async: true
  alias Membrane.Core.Element.State

  describe "when creating new struct" do
    it "should have internal_state field set to nil" do
      %State{internal_state: internal_state} = struct(described_module())
      expect(internal_state) |> to(be_nil())
    end

    it "should have module field set to nil" do
      %State{module: module} = struct(described_module())
      expect(module) |> to(be_nil())
    end

    it "should have playback state set to :stopped" do
      %State{playback: playback} = struct(described_module())
      expect(playback.state) |> to(eq :stopped)
    end

    it "should have source_pads field set to an empty map" do
      %State{pads: pads} = struct(described_module())
      expect(pads) |> to(eq %{})
    end

    it "should have message_bus field set to nil" do
      %State{message_bus: message_bus} = struct(described_module())
      expect(message_bus) |> to(be_nil())
    end
  end
end
