defmodule Membrane.Element.PadTest do
  use ExUnit.Case, async: true
  import Membrane.Pad

  describe "is_pad_ref/1" do
    test "when correct pad ref is given returns true" do
      assert is_pad_ref(:some_pad)
    end

    test "when correct dynamic pad ref is given returns true" do
      assert is_pad_ref({:dynamic, :some_atom, 3})
    end

    test "when incorrect string pad ref is given returns false" do
      refute is_pad_ref("string")
    end

    test "when incorrect tuple with atom pad ref is given returns false" do
      refute is_pad_ref({:tuple_with_atom})
    end

    test "when incorrect tuple with string pad ref is given returns false" do
      refute is_pad_ref({"tuple with sting"})
    end

    test "when incorrect dynamic pad ref is given returns false" do
      refute is_pad_ref({:atom, :some_atom, 3})
    end

    test "when incorrect dynamic pad ref tuple with 2 elements is given return false" do
      refute is_pad_ref({:dynamic, :atom})
    end
  end
end
