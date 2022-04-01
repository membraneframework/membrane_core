defmodule Membrane.Core.Helper.FastMapTest do
  use ExUnit.Case, async: true

  require Membrane.Core.Helper.FastMap, as: FastMap

  doctest FastMap

  @map %{
    list: [],
    counter: 0,
    pad: %{
      :input => %{cnt: 1},
      {:input, 0} => %{cnt: 1}
    },
    and_some: :atom
  }

  test "get_in" do
    some_key = {:input, 0}
    assert 1 == FastMap.get_in!(@map, [:pad, some_key, :cnt])

    assert_raise MatchError, fn ->
      unknown_key = {:input, Enum.random(2..3)}
      FastMap.get_in!(@map, [:pad, unknown_key, :cnt])
    end
  end

  test "set_in" do
    some_key = {:input, 0}
    new_map = FastMap.set_in!(@map, [:pad, some_key, :cnt], 2)
    assert new_map.pad[some_key].cnt == 2

    assert_raise MatchError, fn ->
      unknown_key = {:input, Enum.random(2..3)}
      FastMap.set_in!(@map, [:pad, unknown_key, :cnt], 2)
    end

    assert_raise KeyError, fn ->
      unknown_key = {:input, Enum.random(2..3)}
      FastMap.set_in!(@map, [:pad, unknown_key], :something)
    end
  end

  test "update_in" do
    some_key = {:input, 0}
    new_map = FastMap.update_in!(@map, [:pad, some_key, :cnt], &(&1 + 1))
    assert new_map.pad[some_key].cnt == 2

    assert_raise MatchError, fn ->
      unknown_key = {:input, Enum.random(2..3)}
      FastMap.update_in!(@map, [:pad, unknown_key, :cnt], &(&1 + 1))
    end
  end

  test "get_and_update_in" do
    some_key = {:input, 0}
    assert {1, new_map} = FastMap.get_and_update_in!(@map, [:pad, some_key, :cnt], &{&1, &1 + 1})
    assert new_map.pad[some_key].cnt == 2

    assert_raise MatchError, fn ->
      unknown_key = {:input, Enum.random(2..3)}
      FastMap.get_and_update_in!(@map, [:pad, unknown_key, :cnt], &{&1, &1 + 1})
    end
  end
end
