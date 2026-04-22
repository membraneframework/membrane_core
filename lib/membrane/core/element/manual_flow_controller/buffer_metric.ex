defmodule Membrane.Core.Element.ManualFlowController.BufferMetric do
  @moduledoc false

  alias Membrane.{Buffer, Pad, Payload}
  require Membrane.Logger

  # Sentinel value for timestamp-based metrics: means "no demand set yet".
  @timestamp_init_demand_size -1

  defguardp is_timestamp_unit(unit)
            when unit == :timestamp or
                   (is_tuple(unit) and tuple_size(unit) == 2 and elem(unit, 0) == :timestamp and
                      elem(unit, 1) in [:pts, :dts, :dts_or_pts])

  defguard is_non_timestamp_unit(unit) when unit == :buffers or unit == :bytes

  defguard is_valid_unit(unit) when is_non_timestamp_unit(unit) or is_timestamp_unit(unit)

  @spec buffer_size_approximation(Pad.demand_unit()) :: pos_integer()
  def buffer_size_approximation(:bytes), do: 1500
  def buffer_size_approximation(unit) when is_valid_unit(unit), do: 1

  @spec init_manual_demand_size(Pad.demand_unit()) :: non_neg_integer() | Membrane.Time.t() | -1
  def init_manual_demand_size(unit) when is_non_timestamp_unit(unit), do: 0
  def init_manual_demand_size(unit) when is_timestamp_unit(unit), do: @timestamp_init_demand_size

  @spec buffers_size(Pad.demand_unit(), [Buffer.t()]) ::
          {:ok, non_neg_integer()} | {:error, :operation_not_supported}
  def buffers_size(:buffers, buffers), do: {:ok, length(buffers)}

  def buffers_size(:bytes, buffers) do
    size = Enum.reduce(buffers, 0, fn %Buffer{payload: p}, acc -> acc + Payload.size(p) end)
    {:ok, size}
  end

  def buffers_size(unit, _buffers) when is_timestamp_unit(unit),
    do: {:error, :operation_not_supported}

  @spec split_buffers(
          Pad.demand_unit(),
          [Buffer.t()],
          non_neg_integer() | Membrane.Time.t(),
          Buffer.t() | nil,
          Buffer.t() | nil,
          Pad.ref()
        ) :: {[Buffer.t()], [Buffer.t()]}
  def split_buffers(unit, buffers, demand, first, last, pad_ref) do
    ctx = %{demand: demand, first: first, last: last, pad_ref: pad_ref}
    do_split_buffers(unit, buffers, ctx)
  end

  @spec reduce_demand(
          Pad.demand_unit(),
          non_neg_integer() | Membrane.Time.t(),
          non_neg_integer() | nil
        ) :: non_neg_integer() | Membrane.Time.t()
  def reduce_demand(unit, demand, consumed) when is_non_timestamp_unit(unit),
    do: demand - consumed

  def reduce_demand(unit, demand, _consumed) when is_timestamp_unit(unit), do: demand

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_split_buffers(:buffers, buffers, %{demand: count}),
    do: Enum.split(buffers, count)

  defp do_split_buffers(:bytes, buffers, %{demand: count}),
    do: do_split_buffers_by_bytesize(buffers, count, [])

  defp do_split_buffers(unit, buffers, ctx) when is_timestamp_unit(unit),
    do: do_split_buffers_by_timestamp(unit, buffers, ctx)

  defp do_split_buffers_by_bytesize(buffers, at_pos, acc) when at_pos == 0 or buffers == [] do
    {Enum.reverse(acc), buffers}
  end

  defp do_split_buffers_by_bytesize([%Buffer{payload: p} = buf | rest], at_pos, acc)
       when at_pos > 0 do
    if at_pos < Payload.size(p) do
      {p1, p2} = Payload.split_at(p, at_pos)
      acc = [%Buffer{buf | payload: p1} | acc] |> Enum.reverse()
      rest = [%Buffer{buf | payload: p2} | rest]
      {acc, rest}
    else
      do_split_buffers_by_bytesize(rest, at_pos - Payload.size(p), [buf | acc])
    end
  end

  defp do_split_buffers_by_timestamp(unit, buffers, ctx) do
    %{
      demand: demand_timestamp,
      first: first_consumed,
      last: last_consumed,
      pad_ref: pad_ref
    } = ctx

    cond do
      @timestamp_init_demand_size == demand_timestamp ->
        {[], buffers}

      first_consumed != nil and last_consumed != nil and
          elapsed_timestamp(first_consumed, last_consumed, unit, pad_ref) >= demand_timestamp ->
        warn_demand_not_greater_than_elapsed(
          unit,
          demand_timestamp,
          first_consumed,
          last_consumed,
          pad_ref
        )

        {[], buffers}

      is_nil(first_consumed) and buffers == [] ->
        {[], buffers}

      is_nil(first_consumed) ->
        offset = List.first(buffers) |> get_timestamp!(unit, pad_ref)
        split_timestamp_recursion(unit, buffers, [], ctx, offset, nil)

      true ->
        offset = get_timestamp!(first_consumed, unit, pad_ref)
        split_timestamp_recursion(unit, buffers, [], ctx, offset, last_consumed)
    end
  end

  defp split_timestamp_recursion(unit, [curr_buffer | rest], acc, ctx, offset, prev_buffer) do
    %{demand: demand_timestamp, pad_ref: pad_ref} = ctx
    acc = [curr_buffer | acc]
    curr_timestamp = get_timestamp!(curr_buffer, unit, pad_ref)

    with %Buffer{} <- prev_buffer,
         prev_timestamp = get_timestamp!(prev_buffer, unit, pad_ref),
         true <- curr_timestamp < prev_timestamp do
      warn_non_monotonic_timestamps(unit, prev_timestamp, curr_timestamp, pad_ref)
    end

    if curr_timestamp - offset >= demand_timestamp do
      {Enum.reverse(acc), rest}
    else
      split_timestamp_recursion(unit, rest, acc, ctx, offset, curr_buffer)
    end
  end

  defp split_timestamp_recursion(_unit, [], acc, _ctx, _offset, _prev_buffer) do
    {Enum.reverse(acc), []}
  end

  defp elapsed_timestamp(first_consumed, last_consumed, unit, pad_ref) do
    get_timestamp!(last_consumed, unit, pad_ref) - get_timestamp!(first_consumed, unit, pad_ref)
  end

  defp get_timestamp!(%Buffer{} = buffer, unit, pad_ref) do
    timestamp =
      case unit do
        {:timestamp, :pts} -> buffer.pts
        {:timestamp, :dts} -> buffer.dts
        :timestamp -> Buffer.get_dts_or_pts(buffer)
        {:timestamp, :dts_or_pts} -> Buffer.get_dts_or_pts(buffer)
      end

    if timestamp == nil do
      raise """
      Buffer is missing required #{timestamp_name(unit)} timestamp. \
      All buffers must have a non-nil #{timestamp_name(unit)} when using \
      #{inspect(unit)} as a demand unit for input pads with manual flow control.
      Buffer: #{inspect(buffer)}
      Pad reference: #{inspect(pad_ref)}
      """
    end

    timestamp
  end

  defp timestamp_name({:timestamp, :pts}), do: "PTS"
  defp timestamp_name({:timestamp, :dts}), do: "DTS"

  defp timestamp_name(unit) when unit in [:timestamp, {:timestamp, :dts_or_pts}],
    do: "<DTS || PTS>"

  defp warn_demand_not_greater_than_elapsed(
         unit,
         demand_timestamp,
         first_consumed,
         last_consumed,
         pad_ref
       ) do
    first_timestamp = get_timestamp!(first_consumed, unit, pad_ref)
    last_timestamp = get_timestamp!(last_consumed, unit, pad_ref)
    elapsed = last_timestamp - first_timestamp

    Membrane.Logger.warning("""
    Demanded #{timestamp_name(unit)} should be greater than the elapsed #{timestamp_name(unit)} \
    since the first consumed buffer. Got :demand of #{demand_timestamp}, while the elapsed \
    #{timestamp_name(unit)} equals #{elapsed}. \
    First consumed buffer's #{timestamp_name(unit)}: #{first_timestamp}. \
    Last consumed buffer's #{timestamp_name(unit)}: #{last_timestamp}. \
    No further buffers will be delivered until the element demands a #{timestamp_name(unit)} \
    greater than the elapsed one. \
    """)
  end

  defp warn_non_monotonic_timestamps(unit, prev_timestamp, curr_timestamp, pad_ref) do
    Membrane.Logger.warning("""
    Received buffers with non-monotonic #{timestamp_name(unit)}s. \
    Current buffer's #{timestamp_name(unit)} is #{curr_timestamp}, \
    while the previous buffer's #{timestamp_name(unit)} is #{prev_timestamp}. \
    This may lead to unexpected behavior in elements that have input pad with flow \
    control set to `:manual` and a timestamp demand unit.
    Pad reference: #{inspect(pad_ref)}
    """)
  end
end
