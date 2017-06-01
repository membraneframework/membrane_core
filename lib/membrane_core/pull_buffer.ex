defmodule Membrane.PullBuffer do
  alias Membrane.PullBuffer

  defstruct \
    sink: nil,
    q: nil,
    init_size: 0,
    preferred_size: 100,
    current_size: 0

  @qe Qex

  def new(sink, preferred_size, init_size \\ nil) do
    %PullBuffer{q: @qe.new, sink: sink, preferred_size: preferred_size, init_size: init_size || preferred_size}
  end

  def store(%PullBuffer{q: q, current_size: size} = pb, v) do
    %PullBuffer{pb | q: q |> @qe.push(v), current_size: size + 1}
  end

  defp do_take(%PullBuffer{q: q, init_size: init_size, current_size: size} = pb)
  when size > init_size do
    case q |> @qe.pop do
      {o, q} -> {o, %PullBuffer{pb | q: q, current_size: max(0, size - 1)}}
    end
  end
  defp do_take(%PullBuffer{current_size: size, init_size: init_size} = pb)
  when size < init_size do
    {:empty, pb}
  end
  defp do_take(%PullBuffer{} = pb) do
    take %PullBuffer{pb | init_size: -1}
  end

  def take(%PullBuffer{} = pb) do
    {out, %PullBuffer{current_size: size, preferred_size: pref_size, sink: sink} = pb} = do_take pb
    if {:value, _} |> match?(out) && size < pref_size do
      send sink, {:membrane_demand, 1}
    end
    {out, pb}
  end
  def take(%PullBuffer{current_size: size, preferred_size: pref_size, sink: sink} = pb, count) do
    {_, %PullBuffer{current_size: nsize}} = out = take pb, count, []
    if nsize < size && nsize < pref_size do
      send sink, {:membrane_demand, min(size, pref_size) - nsize}
    end
    out
  end
  defp take(%PullBuffer{} = pb, 0, acc), do: {{:value, acc |> Enum.reverse}, pb}
  defp take(%PullBuffer{} = pb, count, acc) when count > 0 do
    case do_take pb do
      {{:value, v}, npb} -> take npb, count-1, [v|acc]
      {:empty, npb} -> {{:empty, acc |> Enum.reverse}, npb}
    end
  end

  def empty?(%PullBuffer{current_size: size}), do: size == 0

end
