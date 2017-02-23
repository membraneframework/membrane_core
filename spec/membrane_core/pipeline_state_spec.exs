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

    it "should have elements_to_pids field set to an empty map" do
      %Membrane.Pipeline.State{elements_to_pids: elements_to_pids} = struct(described_module())
      expect(elements_to_pids).to eq %{}
    end

    it "should have pids_to_elements field set to an empty map" do
      %Membrane.Pipeline.State{pids_to_elements: pids_to_elements} = struct(described_module())
      expect(pids_to_elements).to eq %{}
    end
  end
end
