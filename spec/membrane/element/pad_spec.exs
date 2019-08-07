defmodule Membrane.Element.PadSpec do
  use ESpec, async: true
  import Membrane.Core.Pad

  describe ".is_pad_ref/1" do
    context "when correct pad ref is given" do
      let :pad_ref_1, do: :some_pad
      let :pad_ref_2, do: {:dynamic, :some_atom, 3}

      it "should return truth" do
        expect(is_pad_ref(pad_ref_1())) |> to(be_true())
      end

      it "should return truth" do
        expect(is_pad_ref(pad_ref_2())) |> to(be_true())
      end
    end

    context "when incorrect pad ref is given" do
      let :pad_ref_1, do: "string"
      let :pad_ref_2, do: {:tuple_with_atom}
      let :pad_ref_3, do: {"tuple with sting"}
      let :pad_ref_4, do: {:atom, :some_atom, 3}
      let :pad_ref_5, do: {:dynamic, :atom}

      it "should return false" do
        expect(is_pad_ref(pad_ref_1())) |> to(be_false())
      end

      it "should return false" do
        expect(is_pad_ref(pad_ref_2())) |> to(be_false())
      end

      it "should return false" do
        expect(is_pad_ref(pad_ref_3())) |> to(be_false())
      end

      it "should return false" do
        expect(is_pad_ref(pad_ref_4())) |> to(be_false())
      end

      it "should return false" do
        expect(is_pad_ref(pad_ref_5())) |> to(be_false())
      end
    end
  end
end
