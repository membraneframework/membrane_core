defmodule Membrane.Element.PadTest do
  use ExUnit.Case, async: true

  import Membrane.Pad

  describe "is_pad_ref/1" do
    test "when correct pad ref is given returns true" do
      assert is_pad_ref(:some_pad)
    end

    test "when correct dynamic pad ref is given returns true" do
      assert is_pad_ref(ref(:some_atom, make_ref()))
    end

    test "when incorrect dynamic pad ref is given returns false" do
      refute is_pad_ref({:dynamic, :some_atom, 3})
    end
  end
end
