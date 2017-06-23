defmodule Membrane.PullBuffer do
  alias Membrane.PullBuffer
  use Membrane.Mixins.Log

  defstruct \
    sink: nil,
    sink_name: nil,
    q: nil,
    init_size: 0,
    preferred_size: 100,
    current_size: 0,
    demand: nil

  @qe Qex

  def new(sink, sink_name, preferred_size, init_size \\ 0) do
    %PullBuffer{
      q: @qe.new,
      sink: sink,
      sink_name: sink_name,
      preferred_size: preferred_size,
      init_size: init_size,
      demand: preferred_size
    }
  end

  def fill(%PullBuffer{demand: demand} = pb), do: handle_demand(pb, demand)

  def store(%PullBuffer{q: q, current_size: size, preferred_size: pref_size, sink_name: sink} = pb, v) do
    if size >= pref_size do warn """
      PullBuffer: received buffers from sink #{inspect sink}, despite
      not requesting them. It is undesirable to send any buffers without demand.
      Unless this is a bug, make sure that doing so is necessary and amount of
      undemanded buffers is controlled and limited.

      Buffers: #{inspect v}
      """
    end

    if is_list v do
      %PullBuffer{pb | q: q |> @qe.join(@qe.new v), current_size: size + length v}
    else
      %PullBuffer{pb | q: q |> @qe.push(v), current_size: size + 1}
    end
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
    {out, pb} = do_take pb
    packOutWithPb out, pb |> handle_demand(1)
  end
  def take(%PullBuffer{current_size: size} = pb, count) do
    {out, %PullBuffer{current_size: new_size} = pb} = take pb, count, []
    packOutWithPb out, pb |> handle_demand(size - new_size)
  end
  defp take(%PullBuffer{} = pb, 0, acc), do: {{:value, acc |> Enum.reverse}, pb}
  defp take(%PullBuffer{} = pb, count, acc) when count > 0 do
    case do_take pb do
      {{:value, v}, npb} -> take npb, count-1, [v|acc]
      {:empty, npb} -> {{:empty, acc |> Enum.reverse}, npb}
    end
  end

  defp packOutWithPb(out, {:ok, pb}), do: {:ok, {out, pb}}
  defp packOutWithPb(_out, {:error, reason}), do: {:error, reason}

  def empty?(%PullBuffer{current_size: size}), do: size == 0

  defp handle_demand(%PullBuffer{sink: sink, sink_name: sink_name,
    current_size: size, preferred_size: pref_size, demand: demand} = pb, new_demand)
  when size < pref_size and demand + new_demand > 0 do
    debug """
      PullBuffer: sending demand of size #{inspect demand + new_demand}
      to sink #{inspect sink_name}
      """
    with :ok <- GenServer.call(sink, {:membrane_demand, demand + new_demand})
    do {:ok, %PullBuffer{pb | demand: 0}}
    else {:error, reason} -> warnError """
      PullBuffer: unable to send demand of size #{inspect demand + new_demand}
      to sink #{inspect sink_name}
      """, reason
    end

  end
  defp handle_demand(%PullBuffer{demand: demand} = pb, new_demand), do:
    {:ok, %PullBuffer{pb | demand: demand + new_demand}}

end
