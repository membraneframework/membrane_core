defmodule Membrane.Pipeline.StateSpec do
  use ESpec, async: true

  describe "when creating new struct" do
    it "should have internal_state field set to nil" do
      %Membrane.Pipeline.State{internal_state: internal_state} = struct(described_module())
      expect(internal_state) |> to(be_nil())
    end

    it "should have module field set to nil" do
      %Membrane.Pipeline.State{module: module} = struct(described_module())
      expect(module) |> to(be_nil())
    end

    it "should have children field set to an empty map" do
      %Membrane.Pipeline.State{children: children} = struct(described_module())
      expect(children) |> to(eq %{})
    end
  end
end
