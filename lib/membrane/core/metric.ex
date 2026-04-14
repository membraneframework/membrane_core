defmodule Membrane.Core.Metric do
  @moduledoc false
  # Unified metric module. All metric logic is dispatched on `demand_unit`, so
  # no separate behaviour implementations are needed.

  alias Membrane.{Buffer, Pad, Payload}
  require Membrane.Logger

  # Sentinel value for timestamp-based metrics: means "no demand set yet".
  @timestamp_init_demand_size -1

  defguard is_timestamp_unit(unit)
           when unit == :timestamp or
                  (is_tuple(unit) and tuple_size(unit) == 2 and elem(unit, 0) == :timestamp and
                     elem(unit, 1) in [:pts, :dts, :dts_or_pts])

  defguard is_non_timestamp_unit(unit) when unit == :buffers or unit == :bytes

  defguard is_valid_unit(unit) when is_non_timestamp_unit(unit) or is_timestamp_unit(unit)

  @spec buffer_size_approximation(Pad.demand_unit()) :: pos_integer()
  def buffer_size_approximation(:bytes), do: 1500
  def buffer_size_approximation(unit) when is_valid_unit(unit), do: 1

  @spec init_manual_demand_size(Pad.demand_unit()) :: non_neg_integer() | Membrane.Time.t()
  def init_manual_demand_size(unit) when is_non_timestamp_unit(unit), do: 0
  def init_manual_demand_size(unit) when is_timestamp_unit(unit), do: @timestamp_init_demand_size

  @spec buffers_size(Pad.demand_unit(), [Buffer.t()] | []) ::
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
          [Buffer.t()] | [],
          non_neg_integer() | Membrane.Time.t(),
          Buffer.t() | nil,
          Buffer.t() | nil
        ) :: {[Buffer.t()], [Buffer.t()]}
  def split_buffers(:buffers, buffers, count, _first, _last),
    do: Enum.split(buffers, count)

  def split_buffers(:bytes, buffers, count, _first, _last),
    do: do_split_bytes(buffers, count, [])

  def split_buffers(unit, buffers, demand_timestamp, first_consumed, last_consumed)
      when is_timestamp_unit(unit) do
    do_split_timestamp_buffers(unit, buffers, demand_timestamp, first_consumed, last_consumed)
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
  # Timestamp-specific functions
  # ---------------------------------------------------------------------------

  @spec is_timestamp_metric?(Pad.demand_unit()) :: boolean()
  def is_timestamp_metric?(unit) when is_timestamp_unit(unit), do: true
  def is_timestamp_metric?(unit) when is_non_timestamp_unit(unit), do: false

  @spec get_timestamp(Pad.timestamp_demand_unit(), Buffer.t()) :: Membrane.Time.t() | nil
  defp get_timestamp({:timestamp, :pts}, %Buffer{pts: pts}), do: pts
  defp get_timestamp({:timestamp, :dts}, %Buffer{dts: dts}), do: dts

  defp get_timestamp(unit, buffer) when unit in [:timestamp, {:timestamp, :dts_or_pts}],
    do: Buffer.get_dts_or_pts(buffer)

  @spec timestamp_name(Pad.timestamp_demand_unit()) :: String.t()
  defp timestamp_name({:timestamp, :pts}), do: "PTS"
  defp timestamp_name({:timestamp, :dts}), do: "DTS"

  defp timestamp_name(unit) when unit in [:timestamp, {:timestamp, :dts_or_pts}],
    do: "<DTS || PTS>"

  @spec generate_metric_specific_warnings(Pad.ref(), [Buffer.t() | nil], Pad.demand_unit()) :: :ok
  def generate_metric_specific_warnings(_pad_ref, [], _unit), do: :ok

  def generate_metric_specific_warnings(pad_ref, buffers, unit) when is_timestamp_unit(unit) do
    [first | rest] = buffers

    _last =
      Enum.reduce(rest, first, fn
        curr_buffer, nil ->
          curr_buffer

        curr_buffer, prev_buffer ->
          prev_timestamp = get_timestamp(unit, prev_buffer)
          curr_timestamp = get_timestamp(unit, curr_buffer)

          if curr_timestamp < prev_timestamp do
            Membrane.Logger.warning("""
            Received buffers with non-monotonic #{timestamp_name(unit)}s. \
            Current buffer's #{timestamp_name(unit)} is #{curr_timestamp}, \
            while the previous buffer's #{timestamp_name(unit)} is #{prev_timestamp}. \
            This may lead to unexpected behavior in elements that have input pad with flow \
            control set to `:manual` and demand unit set to `:timestamp`, `{:timestamp, :dts}` \
            `{:timestamp, :pts}` or `{:timestamp, :dts_or_pts}`.
            Pad reference: #{inspect(pad_ref)}
            """)
          end

          curr_buffer
      end)

    :ok
  end

  @spec assert_non_nil_timestamps!(Pad.ref(), [Buffer.t()], Pad.timestamp_demand_unit()) :: :ok | no_return()
  def assert_non_nil_timestamps!(pad_ref, buffers, unit) when is_timestamp_unit(unit) do
    Enum.each(buffers, fn buffer ->
      if get_timestamp(unit, buffer) == nil do
        raise """
        All buffers must have a non-nil #{timestamp_name(unit)} when using \
        #{inspect(unit)} as a demand unit for input pads with manual flow control.
        Pad reference: #{inspect(pad_ref)}
        Buffer: #{inspect(buffer)}
        """
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_split_bytes(buffers, at_pos, acc) when at_pos == 0 or buffers == [] do
    {Enum.reverse(acc), buffers}
  end

  defp do_split_bytes([%Buffer{payload: p} = buf | rest], at_pos, acc) when at_pos > 0 do
    if at_pos < Payload.size(p) do
      {p1, p2} = Payload.split_at(p, at_pos)
      acc = [%Buffer{buf | payload: p1} | acc] |> Enum.reverse()
      rest = [%Buffer{buf | payload: p2} | rest]
      {acc, rest}
    else
      do_split_bytes(rest, at_pos - Payload.size(p), [buf | acc])
    end
  end

  defp do_split_timestamp_buffers(unit, buffers, demand_timestamp, first_consumed, last_consumed) do
    cond do
      @timestamp_init_demand_size == demand_timestamp ->
        {[], buffers}

      first_consumed != nil and last_consumed != nil and
          get_timestamp(unit, last_consumed) -
            get_timestamp(unit, first_consumed) >= demand_timestamp ->
        Membrane.Logger.warning("""
        Demanded #{timestamp_name(unit)} should be greater than the elapsed #{timestamp_name(unit)} \
        since the first consumed buffer. Got :demand of #{demand_timestamp}, while the elapsed \
        #{timestamp_name(unit)} equals \
        #{get_timestamp(unit, last_consumed) - get_timestamp(unit, first_consumed)}. \
        Demanding a #{timestamp_name(unit)} that is not greater than the elapsed one \
        won't result in handling any further buffers, until the element demands a #{timestamp_name(unit)} \
        greater than the elapsed one. \
        """)

        {[], buffers}

      is_nil(first_consumed) and buffers == [] ->
        {[], buffers}

      is_nil(first_consumed) ->
        offset = get_timestamp(unit, List.first(buffers))
        split_timestamp_recursion(unit, buffers, [], demand_timestamp, offset)

      true ->
        offset = get_timestamp(unit, first_consumed)
        split_timestamp_recursion(unit, buffers, [], demand_timestamp, offset)
    end
  end

  defp split_timestamp_recursion(unit, [buffer | rest], acc, demand_timestamp, offset) do
    acc = [buffer | acc]
    buffer_timestamp = get_timestamp(unit, buffer)

    if buffer_timestamp - offset >= demand_timestamp do
      {Enum.reverse(acc), rest}
    else
      split_timestamp_recursion(unit, rest, acc, demand_timestamp, offset)
    end
  end

  defp split_timestamp_recursion(_unit, [], acc, _demand_timestamp, _offset) do
    {Enum.reverse(acc), []}
  end
end
