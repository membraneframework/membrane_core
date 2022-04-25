Mix.install([:benchee, {:membrane_core, path: "."}])
defmodule Benchmark do
  alias Membrane.Core.Helper.FastMap

  require FastMap

  def run() do
    range = 1..10_000
    map = %{
      list: [],
      counter: 0,
      pad: %{
        :input => %{cnt: 1},
        {:input, 0} => %{cnt: 1}
      },
      and_some: :atom
    }
    not_nested = %{
      fast_map: fn ->
        Enum.reduce(range, map, fn i, map ->
          FastMap.update_in(map, [:counter], & &1 + i)
        end)
      end,
      map: fn ->
        Enum.reduce(range, map, fn i, map ->
          Map.update!(map, :counter, & &1 + i)
        end)
      end
    }
    Benchee.run(not_nested)
    nested = %{
      fast_map: fn ->
        Enum.reduce(range, map, fn i, map ->
          FastMap.update_in(map, [:pad, :input, :cnt], & &1 + i)
        end)
      end,
      update_in: fn ->
        Enum.reduce(range, map, fn i, map ->
          update_in(map[:pad][:input][:cnt], & &1 + i)
        end)
      end
    }
    Benchee.run(nested)
  end
end

Benchmark.run()
