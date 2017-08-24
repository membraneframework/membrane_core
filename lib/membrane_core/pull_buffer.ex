defmodule Membrane.PullBuffer do
  alias Membrane.PullBuffer
  use Membrane.Helper
  use Membrane.Mixins.Log, tags: :core
  alias Membrane.Buffer

  defstruct \
    sink: nil,
    sink_name: nil,
    q: nil,
    init_size: 0,
    preferred_size: 100,
    current_size: 0,
    demand: nil,
    metric: nil

  @qe Qex

  @non_buf_types [:event, :caps]

  def new(sink, sink_name, demand_in, props) do
    metric = Buffer.Metric.from_unit demand_in
    preferred_size = metric.pullbuffer_preferred_size
    %PullBuffer{
      q: @qe.new,
      sink: sink,
      sink_name: sink_name,
      preferred_size: preferred_size,
      init_size: props[:init_size] || 0,
      demand: preferred_size,
      metric: metric,
    }
  end

  def fill(%PullBuffer{} = pb), do: handle_demand(pb, 0)
    |> or_warn_error("Unable to fill PullBuffer: #{inspect pb}")

  def store(pb, type \\ :buffers, v)

  def store(%PullBuffer{current_size: size, preferred_size: pref_size, sink_name: sink} = pb, :buffers, v)
  when is_list(v)
  do
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
  def store(pb, :buffer, v), do: store(pb, :buffers, [v])

  def store(%PullBuffer{q: q} = pb, type, v) when type in @non_buf_types do
    report "Storing #{type}", pb
    {:ok, %PullBuffer{pb | q: q |> @qe.push({:non_buffer, type, v})}}
  end

  defp do_store_buffers(%PullBuffer{q: q, current_size: size, metric: metric} = pb, v) do
    buf_cnt = v |> metric.buffers_size
    report "Storing #{inspect buf_cnt} buffers", pb
    %PullBuffer{
      pb | q: q |> @qe.push({:buffers, v, buf_cnt}), current_size: size + buf_cnt
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

  defp do_take(
    %PullBuffer{q: q, current_size: size, init_size: init_size, metric: metric} = pb, count)
  when init_size |> is_nil or size > init_size
  do
    {out, nq} = q |> q_pop(count, metric)
    {out, %PullBuffer{pb | q: nq, current_size: max(0, size - count)}}
  end

  defp do_take(%PullBuffer{current_size: size, init_size: init_size} = pb, _count)
  when size < init_size
  do
    report """
      Forbidden to take buffers, as PullBuffer did not reach initial size
      of #{inspect init_size}, returning :empty
      """, pb
    {{:empty, []}, pb}
  end
  defp do_take(%PullBuffer{current_size: size, init_size: init_size} = pb, count)
  when size == init_size
  do
    do_take %PullBuffer{pb | init_size: nil}, count
  end

  defp q_pop(q, count, metric, acc \\ [])
  defp q_pop(q, count, metric, acc) when count > 0
  do
    q |> @qe.pop |> (case do
        {{:value, {:buffers, b, buf_cnt}}, nq} when count >= buf_cnt ->
          q_pop nq, count - buf_cnt, metric, [{:buffers, b, buf_cnt}|acc]
        {{:value, {:buffers, b, buf_cnt}}, nq} when count < buf_cnt ->
          {b, back} = b |> metric.split_buffers(count)
          nq = nq |> @qe.push_front({:buffers, back, buf_cnt - count})
          {{:value, [{:buffers, b, count,}|acc] |> Enum.reverse}, nq}
        {:empty, nq} ->
          {{:empty, acc |> Enum.reverse}, nq}
        {{:value, {:non_buffer, type, e}}, nq} ->
          q_pop nq, count, metric, [{type, e}|acc]
      end)
  end
  defp q_pop(q, 0, metric, acc) do
    q |> @qe.pop |> (case do
        {{:value, {:non_buffer, type, e}}, nq} -> q_pop nq, 0, metric, [{type, e}|acc]
        _ -> {{:value, acc |> Enum.reverse}, q}
      end)
  end

  def empty?(%PullBuffer{current_size: size, init_size: init_size}), do:
    size == 0 || (init_size != nil && size < init_size)

  defp handle_demand(%PullBuffer{sink: {other_pid, other_name}, sink_name: sink_name,
    current_size: size, preferred_size: pref_size, demand: demand} = pb, new_demand)
  when size < pref_size and demand + new_demand > 0 do
    report """
      Sending demand of size #{inspect demand + new_demand}
      to sink #{inspect sink_name}
      """, pb
    send other_pid, {:membrane_demand, {demand + new_demand, other_name}}
    {:ok, %PullBuffer{pb | demand: 0}}
  end
  defp handle_demand(%PullBuffer{demand: demand} = pb, new_demand), do:
    {:ok, %PullBuffer{pb | demand: demand + new_demand}}

  defp report(msg, %PullBuffer{current_size: size, preferred_size: pref_size}),
  do: debug """
    PullBuffer: #{msg}
    PullBuffer size: #{inspect size}, PullBuffer preferred size: #{inspect pref_size}
    """

end
