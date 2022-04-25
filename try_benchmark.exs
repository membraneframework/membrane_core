Mix.install([:benchee, {:membrane_core, path: "."}])

range = 1..10_000

map = %{x: 0, y: 0, z: 0, a: 1, b: 2}

cases = %{
  multi: fn ->
    Enum.map_reduce(range, map, fn _i, acc ->
      case acc do
        %{x: 1} -> raise "x"
        %{y: 2} -> raise "y"
        %{z: 3} -> raise "z"
        %{a: a, b: b} -> {{a, b}, acc}
      end
    end)
  end,
  single: fn ->
    Enum.map_reduce(range, map, fn _i, acc ->
      with %{x: 0, y: 0, z: 0, a: a, b: b} <- acc do
        {{a, b}, acc}
      else
        %{x: 1} -> raise "x"
        %{y: 2} -> raise "y"
        %{z: 3} -> raise "z"
      end
    end)
  end
}

Benchee.run(cases)
