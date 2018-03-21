defmodule Membrane.Helper.Struct do
  import Kernel, except: [get_in: 2, put_in: 2, update_in: 3, get_and_update_in: 3, pop_in: 2]
  use Membrane.Helper

  def get_in(map, []), do: map
  def get_in(map, keys), do: map |> Kernel.get_in(keys |> map_keys)

  def put_in(_map, [], v), do: v
  def put_in(map, keys, v), do: map |> Kernel.put_in(keys |> map_keys, v)

  def update_in(map, [], f), do: f.(map)
  def update_in(map, keys, f), do: map |> Kernel.update_in(keys |> map_keys, f)

  def get_and_update_in(map, [], f), do: f.(map)
  def get_and_update_in(map, keys, f), do: map |> Kernel.get_and_update_in(keys |> map_keys, f)

  def pop_in(map, []), do: {nil, map}
  def pop_in(map, keys), do: map |> Kernel.pop_in(keys |> map_keys)

  def remove_in(map, keys), do: pop_in(map, keys) ~> ({_out, map} -> map)

  defp map_keys(keys), do: keys |> Helper.listify() |> Enum.map(&Access.key(&1, nil))
end
