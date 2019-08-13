defmodule Membrane.SpecSpec do
  use ESpec, async: true

  describe "when creating new struct" do
    it "should have children field set to empty list" do
      %Membrane.Spec{children: children} = struct(described_module())
      expect(children) |> to(eq [])
    end

    it "should have links field set to empty map" do
      %Membrane.Spec{links: links} = struct(described_module())
      expect(links) |> to(eq %{})
    end
  end
end
