defmodule MockCaps do
  defstruct integer: 42,
            string: "mock"
end

defmodule Membrane.Element.Manager.CapsMatcherSpec do
  use ESpec

  describe "match/2" do
    context "given example caps" do
      let :caps, do: %MockCaps{}
      it "should match empty spec" do
        expect(described_module().match(%{}, caps())).to be_true()
      end
      it "should match proper type" do
        expect(described_module().match(%{type: MockCaps}, caps())).to be_true()
      end

      it "should match value within specified range" do
        expect(described_module().match(%{integer: {10, 50}}, caps())).to be_true()
      end

      it "should match when value is in the specified list" do
        expect(described_module().match(%{integer: [4, 42, 421]}, caps())).to be_true()
        expect(described_module().match(%{string: ["ala", "ma", "kota", "mock"]}, caps())).to be_true()
      end

      it "shouldn't match invalid type" do
        expect(described_module().match(%{type: MapSet}, caps())).to be_false()
      end

      it "shouldn't match value outside the specified range" do
        expect(described_module().match(%{integer: {10, 40}}, caps())).to be_false()
      end

      it "shouldn't match when value is not in the specified list" do
        expect(described_module().match(%{integer: [10, 40, 100, 90, 2]}, caps())).to be_false()
        expect(described_module().match(%{string: ["ala", "ma", "kota", "qwerty"]}, caps())).to be_false()
      end

      it "should return false for partial match" do
        expect(described_module().match(%{type: MapSet, integer: {10, 45}}, caps())).to be_false()
        expect(described_module().match(%{type: MockCaps, integer: {10, 35}}, caps())).to be_false()
        expect(described_module().match(%{integer: {10, 45}, string: ["none", "shall", "pass"]}, caps())).to be_false()
        expect(described_module().match(%{integer: {10, 35}, string: ["mock", "shall", "pass"]}, caps())).to be_false()
        expect(described_module().match(%{type: MockCaps, integer: {10, 35}, string: ["imma", "teh", "mock"]}, caps())).to be_false()
      end

      it "should return true when one spec from list matches" do
        failing = %{type: MapSet, integer: 42, string: "mock"}
        proper = %{type: MockCaps, integer: {10, 50}}

        expect(described_module().match(failing, caps())).to be_false()
        expect(described_module().match(proper, caps())).to be_true()
        expect(described_module().match([failing, proper], caps())).to be_true()
      end
    end
  end
end
