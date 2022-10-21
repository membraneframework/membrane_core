defmodule Membrane.CapsMatcherTest do
  use ExUnit.Case, async: true

  import Membrane.Caps.Matcher, only: [range: 2, one_of: 1]

  alias Membrane.Caps.Matcher
  alias Membrane.Caps.Mock, as: MockCaps

  describe "validate_specs/1" do
    test "should succeed when specs have all fields of caps" do
      should_be_valid({MockCaps, integer: 1, string: "m"})
    end

    test "should succeed when specs have some fields of caps" do
      should_be_valid({MockCaps, integer: 1})
      should_be_valid({MockCaps, string: "m"})
    end

    test "should succeed when specs only specify type" do
      should_be_valid(MockCaps)
    end

    test "should succeed when specs are :any" do
      should_be_valid(:any)
    end

    test "should fail when specs contain key not present in caps" do
      should_be_invalid({MockCaps, integer: 1, string: "m", invalid: 42})
      should_be_invalid({MockCaps, nope: 42})
    end

    test "should fail when empty tuple any is used as specs" do
      should_be_invalid({})
    end
  end

  describe "match?/2 given invalid caps" do
    setup do
      {:ok, caps: :not_caps}
    end

    test "should match :any", context do
      should_match(:any, context.caps)
    end

    test "should raise error for any valid spec", context do
      raising_fun = fn -> Matcher.match?(MockCaps, context.caps) end
      assert_raise FunctionClauseError, raising_fun
    end
  end

  describe "given example caps" do
    setup do
      {:ok, caps: %MockCaps{}}
    end

    test "should match with :any as spec", context do
      should_match(:any, context.caps)
    end

    test "should match proper type", context do
      should_match(MockCaps, context.caps)
    end

    test "should match value within specified range", context do
      should_match({MockCaps, integer: range(10, 50)}, context.caps)
    end

    test "should match when value is in the specified list", context do
      should_match({MockCaps, integer: one_of([4, 42, 421])}, context.caps)
      should_match({MockCaps, string: one_of(["ala", "ma", "kota", "mock"])}, context.caps)
    end

    test "should match when valid range spec is nested in list", context do
      should_match({MockCaps, integer: one_of([4, range(30, 45), 421])}, context.caps)
    end

    test "shouldn't match invalid type", context do
      should_not_match(MapSet, context.caps)
    end

    test "shouldn't match value outside the specified range", context do
      should_not_match({MockCaps, integer: range(10, 40)}, context.caps)
    end

    test "shouldn't match when value is not in the specified list", context do
      should_not_match({MockCaps, integer: one_of([10, 40, 100, 90, 2])}, context.caps)
      should_not_match({MockCaps, string: one_of(["ala", "ma", "kota", "qwerty"])}, context.caps)
    end

    test "shouldn't match partially matching caps", context do
      should_not_match({MapSet, integer: range(10, 45)}, context.caps)
      should_not_match({MockCaps, integer: range(10, 35)}, context.caps)

      should_not_match(
        {MockCaps, integer: range(10, 45), string: one_of(["none", "shall", "pass"])},
        context.caps
      )

      should_not_match(
        {MockCaps, integer: range(10, 35), string: one_of(["imma", "teh", "mock"])},
        context.caps
      )
    end

    test "should succeed when one spec from list matches", context do
      failing = {MapSet, integer: 42, string: "mock"}
      proper = {MockCaps, integer: range(10, 50)}

      should_not_match(failing, context.caps)
      should_match(proper, context.caps)
      should_match([failing, proper], context.caps)
    end

    test "should fail when none of the specs from list matches", context do
      failing = {MapSet, integer: 42, string: "mock"}
      failing_too = {MockCaps, integer: range(10, 30)}

      should_not_match(failing, context.caps)
      should_not_match(failing_too, context.caps)
      should_not_match([failing, failing_too], context.caps)
    end
  end

  defp should_be_valid(specs) do
    assert Matcher.validate_specs(specs) == :ok
  end

  defp should_be_invalid(specs) do
    assert {:error, _error} = Matcher.validate_specs(specs)
  end

  defp should_match(specs, caps) do
    assert Matcher.match?(specs, caps) == true
  end

  defp should_not_match(specs, caps) do
    assert Matcher.match?(specs, caps) == false
  end
end
