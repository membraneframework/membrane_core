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

  def fill(%PullBuffer{} = pb), do: handle_demand(pb, 0)
    |> orWarnError("Unable to fill PullBuffer: #{inspect pb}")

  def store(%PullBuffer{q: q, current_size: size, preferred_size: pref_size, sink_name: sink} = pb, v) do
    if size >= pref_size do warn """
      PullBuffer: received buffers from sink #{inspect sink}, despite
      not requesting them. It is undesirable to send any buffers without demand.
      Unless this is a bug, make sure that doing so is necessary and amount of
      undemanded buffers is controlled and limited.

      Buffers: #{inspect v}

      PullBuffer #{inspect pb}
      """
    end

    report "Storing #{inspect (if is_list v do length v else 1 end)} buffers", pb
    if is_list v do
      %PullBuffer{pb | q: q |> @qe.join(@qe.new v), current_size: size + length v}
    else
      %PullBuffer{pb | q: q |> @qe.push(v), current_size: size + 1}
    end
  end

  def take(%PullBuffer{current_size: size} = pb, count \\ 1) when count >= 0 do
    report "Taking #{inspect count} buffers", pb
    {out, %PullBuffer{current_size: new_size} = pb} = do_take pb, count
    with {:ok, pb} <- pb |> handle_demand(size - new_size)
    do {:ok, {out, pb}}
    end
  end

  defp do_take(pb, 1), do: do_take(pb)
  defp do_take(pb, count), do: do_take(pb, count, [])

  defp do_take(%PullBuffer{q: q, init_size: init_size, current_size: size} = pb)
  when size > init_size do
    {o, q} = q |> @qe.pop
    if o == :empty do report "underrun", pb end
    {o, %PullBuffer{pb | q: q, current_size: max(0, size - 1)}}
  end
  defp do_take(%PullBuffer{current_size: size, init_size: init_size} = pb)
  when size < init_size do
    report """
      Forbidden to take buffers, as PullBuffer did not reach initial size
      of #{inspect init_size}, returning :empty
      """, pb
    {:empty, pb}
  end
  defp do_take(%PullBuffer{} = pb), do: do_take(%PullBuffer{pb | init_size: -1})

  defp do_take(%PullBuffer{} = pb, 0, acc), do: {{:value, acc |> Enum.reverse}, pb}
  defp do_take(%PullBuffer{} = pb, count, acc) do
    case do_take pb do
      {{:value, v}, npb} -> do_take npb, count-1, [v|acc]
      {:empty, npb} -> {{:empty, acc |> Enum.reverse}, npb}
    end
  end

  def empty?(%PullBuffer{current_size: size, init_size: init_size}), do:
    size == 0 || size < init_size

  defp handle_demand(%PullBuffer{sink: sink, sink_name: sink_name,
    current_size: size, preferred_size: pref_size, demand: demand} = pb, new_demand)
  when size < pref_size and demand + new_demand > 0 do
    report """
      Sending demand of size #{inspect demand + new_demand}
      to sink #{inspect sink_name}
      """, pb
    with :ok <- GenServer.call(sink, {:membrane_demand, demand + new_demand})
    do {:ok, %PullBuffer{pb | demand: 0}}
    else {:error, reason} -> warnError """
      PullBuffer: unable to send demand of size #{inspect demand + new_demand}
      to sink #{inspect sink_name}

      PullBuffer #{inspect pb}
      """, reason
    end

  end
  defp handle_demand(%PullBuffer{demand: demand} = pb, new_demand), do:
    {:ok, %PullBuffer{pb | demand: demand + new_demand}}

  defp report(msg, %PullBuffer{current_size: size, preferred_size: pref_size}),
  do: debug """
    PullBuffer: #{msg}
    PullBuffer size: #{inspect size}, PullBuffer preferred size: #{inspect pref_size}
    """

end
