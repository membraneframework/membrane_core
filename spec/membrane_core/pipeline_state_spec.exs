defmodule Membrane.Pipeline.StateSpec do
  use ESpec, async: true

  describe "when creating new struct" do
    it "should have internal_state field set to nil" do
      %Membrane.Pipeline.State{internal_state: internal_state} = struct(described_module())
      expect(internal_state).to be_nil()
    end

    it "should have module field set to nil" do
      %Membrane.Pipeline.State{module: module} = struct(described_module())
      expect(module).to be_nil()
    end

    it "should have children_to_pids field set to an empty map" do
      %Membrane.Pipeline.State{children_to_pids: children_to_pids} = struct(described_module())
      expect(children_to_pids).to eq %{}
    end

    it "should have pids_to_children field set to an empty map" do
      %Membrane.Pipeline.State{pids_to_children: pids_to_children} = struct(described_module())
      expect(pids_to_children).to eq %{}
    end
  end
end
