defmodule MockCaps do
  defstruct integer: 42,
            string: "mock"
end

defmodule Membrane.Element.Manager.CapsMatcherSpec do
  use ESpec

  describe "match/2" do
    context "given example caps" do
      let :caps, do: %MockCaps{}

      def should_match(spec) do
        expect(described_module().match(spec, caps())).to be_true()
      end

      def should_not_match(spec) do
        expect(described_module().match(spec, caps())).to be_false()
      end

      it "should match empty spec" do
        should_match(%{})
      end
      it "should match proper type" do
        should_match(%{type: MockCaps})
      end

      it "should match value within specified range" do
        should_match(%{integer: {10, 50}})
      end

      it "should match when value is in the specified list" do
        should_match(%{integer: [4, 42, 421]})
        should_match(%{string: ["ala", "ma", "kota", "mock"]})
      end

      it "shouldn't match invalid type" do
        should_not_match(%{type: MapSet})
      end

      it "shouldn't match value outside the specified range" do
        should_not_match(%{integer: {10, 40}})
      end

      it "shouldn't match when value is not in the specified list" do
        should_not_match(%{integer: [10, 40, 100, 90, 2]})
        should_not_match(%{string: ["ala", "ma", "kota", "qwerty"]})
      end

      it "should return false for partial match" do
        should_not_match(%{type: MapSet, integer: {10, 45}})
        should_not_match(%{type: MockCaps, integer: {10, 35}})
        should_not_match(%{integer: {10, 45}, string: ["none", "shall", "pass"]})
        should_not_match(%{integer: {10, 35}, string: ["mock", "shall", "pass"]})
        should_not_match(%{type: MockCaps, integer: {10, 35}, string: ["imma", "teh", "mock"]})
      end

      it "should return true when one spec from list matches" do
        failing = %{type: MapSet, integer: 42, string: "mock"}
        proper = %{type: MockCaps, integer: {10, 50}}

        should_not_match(failing)
        should_match(proper)
        should_match([failing, proper])
      end
    end
  end
end
