defmodule MockCaps do
  defstruct integer: 42,
            string: "mock"
end

defmodule Membrane.Element.Manager.CapsMatcherSpec do
  use ESpec

  describe "validate_specs!/1" do
    it "should succeed when specs have all fields of caps" do
      expect(described_module().validate_specs!({MockCaps, integer: 1, string: "m"})).to(eq :ok)
    end

    it "should succeed when specs have some fields of caps" do
      expect(described_module().validate_specs!({MockCaps, integer: 1})).to(eq :ok)
      expect(described_module().validate_specs!({MockCaps, string: "m"})).to(eq :ok)
    end

    it "should succeed when specs only specify type" do
      expect(described_module().validate_specs!({MockCaps})).to(eq :ok)
    end

    it "should succeed when specs are :any" do
      expect(described_module().validate_specs!(:any)).to(eq :ok)
    end

    it "should fail when specs contain key not present in caps" do
      some_valid = fn -> described_module().validate_specs!({MockCaps, integer: 1, string: "m", invalid: 42}) end
      only_invalid = fn -> described_module().validate_specs!({MockCaps, nope: 42}) end
      expect(some_valid).to(raise_exception(ArgumentError))
      expect(only_invalid).to(raise_exception(ArgumentError))
    end

    it "should fail when atom other than any is used as specs" do
      atom_as_spec = fn -> described_module().validate_specs!(:not_spec) end
      expect(atom_as_spec).to(raise_exception(ArgumentError))
    end

    it "should fail when empty tuple any is used as specs" do
      empty_tuple_as_spec = fn -> described_module().validate_specs!({}) end
      expect(empty_tuple_as_spec).to(raise_exception(ArgumentError))
    end
  end

  describe "match/2" do
    def should_match(spec, caps) do
      expect(described_module().match(spec, caps)).to(be_true())
    end

    def should_not_match(spec, caps) do
      expect(described_module().match(spec, caps)).to(be_false())
    end

    context "given invalid caps" do
      let(:caps, do: :not_caps)

      it "should match :any" do
        should_match(:any, caps())
      end

      it "should raise error for any valid spec" do
        raising_fun = fn -> described_module().match({MockCaps}, caps()) end
        expect(raising_fun).to(raise_exception(ArgumentError))
      end
    end

    context "given example caps" do
      let(:caps, do: %MockCaps{})

      it "should match with :any as spec" do
        should_match(:any, caps())
      end

      it "should match proper type" do
        should_match({MockCaps}, caps())
      end

      it "should match value within specified range" do
        should_match({MockCaps, integer: {10, 50}}, caps())
      end

      it "should match when value is in the specified list" do
        should_match({MockCaps, integer: [4, 42, 421]}, caps())
        should_match({MockCaps, string: ["ala", "ma", "kota", "mock"]}, caps())
      end

      it "shouldn't match invalid type" do
        should_not_match({MapSet}, caps())
      end

      it "shouldn't match value outside the specified range" do
        should_not_match({MockCaps, integer: {10, 40}}, caps())
      end

      it "shouldn't match when value is not in the specified list" do
        should_not_match({MockCaps, integer: [10, 40, 100, 90, 2]}, caps())
        should_not_match({MockCaps, string: ["ala", "ma", "kota", "qwerty"]}, caps())
      end

      it "shouldn't match partially matching caps" do
        should_not_match({MapSet, integer: {10, 45}}, caps())
        should_not_match({MockCaps, integer: {10, 35}}, caps())
        should_not_match({MockCaps, integer: {10, 45}, string: ["none", "shall", "pass"]}, caps())
        should_not_match({MockCaps, integer: {10, 35}, string: ["imma", "teh", "mock"]}, caps())
      end

      it "should succeed when one spec from list matches" do
        failing = {MapSet, integer: 42, string: "mock"}
        proper = {MockCaps, integer: {10, 50}}

        should_not_match(failing, caps())
        should_match(proper, caps())
        should_match([failing, proper], caps())
      end

      it "should fail when none of the specs from list matches" do
        failing = {MapSet, integer: 42, string: "mock"}
        failing_too = {MockCaps, integer: {10, 30}}

        should_not_match(failing, caps())
        should_not_match(failing_too, caps())
        should_not_match([failing, failing_too], caps())
      end

      it "should raise exception when specs are invalid" do
        raising_fun = fn -> described_module().match(:not_spec, caps()) end
        expect(raising_fun).to(raise_exception(ArgumentError))
      end
    end
  end
end
