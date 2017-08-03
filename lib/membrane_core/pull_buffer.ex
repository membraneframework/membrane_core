defmodule Membrane.PullBuffer do
  alias Membrane.PullBuffer
  use Membrane.Helper
  use Membrane.Mixins.Log, tags: :core

  defstruct \
    sink: nil,
    sink_name: nil,
    q: nil,
    init_size: 0,
    preferred_size: 100,
    current_size: 0,
    demand: nil

  @qe Qex

  @non_buf_types [:event, :caps]

  def new(sink, sink_name, props) do
    preferred_size = props |> Keyword.get(:preferred_size, 10)
    %PullBuffer{
      q: @qe.new,
      sink: sink,
      sink_name: sink_name,
      preferred_size: preferred_size,
      init_size: props |> Keyword.get(:init_size, 10),
      demand: preferred_size
    }
  end

  def fill(%PullBuffer{} = pb), do: handle_demand(pb, 0)
    |> or_warn_error("Unable to fill PullBuffer: #{inspect pb}")

  def store(pb, type \\ :buffers, v)

  def store(%PullBuffer{current_size: size, preferred_size: pref_size, sink_name: sink} = pb, :buffers, v) do
    if size >= pref_size do warn """
      PullBuffer: received buffers from sink #{inspect sink}, despite
      not requesting them. It is undesirable to send any buffers without demand.
      Unless this is a bug, make sure that doing so is necessary and amount of
      undemanded buffers is controlled and limited.

      Buffers: #{inspect v}

      PullBuffer #{inspect pb}
      """
    end
    {:ok, do_store_buffers(pb, v)}
  end
  def store(pb, :buffers, v), do: store(pb, :buffers, [v])

  def store(%PullBuffer{q: q} = pb, type, v) when type in @non_buf_types do
    report "Storing #{type}", pb
    {:ok, %PullBuffer{pb | q: q |> @qe.push({type, v})}}
  end

  defp do_store_buffers(%PullBuffer{q: q, current_size: size} = pb, v)
  when is_list v do
    report "Storing #{inspect length v} buffers", pb
    %PullBuffer{
      pb | q: (@qe.join q, v |> Enum.map(&{:buffer, &1}) |> @qe.new), current_size: size + length v
    }
  end

  def take(%PullBuffer{current_size: size} = pb, count)
  when count >= 0 do
    report "Taking #{inspect count} buffers", pb
    {out, %PullBuffer{current_size: new_size} = pb} = do_take pb, count
    with {:ok, pb} <- pb |> handle_demand(size - new_size)
    do {:ok, {out, pb}}
    end
  end

  defp do_take(%PullBuffer{current_size: size, init_size: init_size} = pb, count) do
    cond do
      size > init_size -> do_take_r pb, count
      size < init_size ->
        report """
          Forbidden to take buffers, as PullBuffer did not reach initial size
          of #{inspect init_size}, returning :empty
          """, pb
        {{:empty, []}, pb}
      true -> do_take_r %PullBuffer{pb | init_size: -1}, count
    end
  end

  defp do_take_r(pb, count, acc \\ [])
  defp do_take_r(%PullBuffer{} = pb, 0, acc) do
    pb |> do_take_pop |> (case do
      {{:value, {type, e}}, npb} when type in @non_buf_types ->
        do_take_r npb, 0, [{type, e}|acc]
      _ -> {{:value, acc |> Enum.reverse |> join_buffers}, pb}
      end)
  end
  defp do_take_r(%PullBuffer{} = pb, count, acc) do
    pb |> do_take_pop |> (case do
      {{:value, {:buffer, b}}, npb} -> do_take_r npb, count-1, [{:buffer, b}|acc]
      {:empty, npb} -> {{:empty, acc |> Enum.reverse |> join_buffers}, npb}
      {{:value, {type, e}}, npb} when type in @non_buf_types ->
        do_take_r npb, count, [{type, e}|acc]
    end)
  end

  defp do_take_pop(%PullBuffer{q: q, current_size: size} = pb) do
    q |> @qe.pop |> case do
      {{:value, v}, nq} -> {{:value, v}, %PullBuffer{pb | q: nq, current_size: size - 1}}
      {:empty, nq} -> {:empty, %PullBuffer{pb | q: nq}}
    end
  end

  defp join_buffers(output) do
    output |> Helper.Enum.chunk_by(
        fn
          {:buffer, _}, {:buffer, _} -> true
          _, _ -> false
        end,
        fn
          [{type, v}] when type in @non_buf_types -> {type, v}
          buffers -> {:buffers, buffers |> Enum.map(fn {:buffer, b} -> b end)}
        end
      )
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
    with :ok <- Helper.send(sink, {:membrane_demand, demand + new_demand})
    do {:ok, %PullBuffer{pb | demand: 0}}
    else {:error, reason} -> warn_error """
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
