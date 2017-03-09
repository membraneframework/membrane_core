defmodule Membrane.Helper.EnumSpec do
  use ESpec, async: true

  describe ".zip_longest/1" do
    context "in usual case" do
      it "should zip list of lists into list of tuples" do
        expect(described_module().zip_longest [[1, 2, 3], [4, 5, 6, 7], [8, 9]]).to eq [[1, 4, 8], [2, 5, 9], [3, 6], [7]]
      end
    end
  end

  describe ".unzip/2" do
    context "in usual case" do
      it "should unzip list of tuples to tuple of lists" do
        expect(described_module().unzip([{1, 2, 3}, {4, 5, 6}], 3)). to eq {:ok, {[1, 4], [2, 5], [3, 6]}}
      end
    end
    context "if there is a tuple of not-fitting length" do
      it "should break recursion and return error" do
        expect(described_module().unzip([{1, 2, 3}, {4, 5}], 3)). to eq {:error, "tuple {4, 5} is not 3-element long"}
      end
    end
  end
end
