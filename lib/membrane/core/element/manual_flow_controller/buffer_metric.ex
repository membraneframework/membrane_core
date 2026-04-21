defmodule Membrane.Core.Element.ManualFlowController.BufferMetric do
  @moduledoc false

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
  # Timestamp-specific functions
  # ---------------------------------------------------------------------------

  @spec is_timestamp_metric?(Pad.demand_unit()) :: boolean()
  def is_timestamp_metric?(unit) when is_timestamp_unit(unit), do: true
  def is_timestamp_metric?(unit) when is_non_timestamp_unit(unit), do: false

  @spec get_timestamp!(Buffer.t(), Pad.timestamp_demand_unit(), Pad.ref() | nil) ::
          Membrane.Time.t()
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
      Buffer is missing required #{timestamp_name(unit)} timestamp for demand unit #{inspect(unit)}.
      Buffer: #{inspect(buffer)}
      Pad reference: #{inspect(pad_ref)}
      """
    end

    timestamp
  end

  @spec timestamp_name(Pad.timestamp_demand_unit()) :: String.t()
  defp timestamp_name({:timestamp, :pts}), do: "PTS"
  defp timestamp_name({:timestamp, :dts}), do: "DTS"

  defp timestamp_name(unit) when unit in [:timestamp, {:timestamp, :dts_or_pts}],
    do: "<DTS || PTS>"

  @spec generate_metric_specific_warnings(Pad.ref(), [Buffer.t() | nil], Pad.demand_unit()) :: :ok
  def generate_metric_specific_warnings(_pad_ref, _buffers, unit)
      when is_non_timestamp_unit(unit),
      do: :ok

  def generate_metric_specific_warnings(_pad_ref, [], _unit), do: :ok

  def generate_metric_specific_warnings(pad_ref, buffers, unit) when is_timestamp_unit(unit) do
    [first | rest] = buffers

    _last =
      Enum.reduce(rest, first, fn
        curr_buffer, nil ->
          curr_buffer

        curr_buffer, prev_buffer ->
          prev_timestamp = get_timestamp!(prev_buffer, unit, nil)
          curr_timestamp = get_timestamp!(curr_buffer, unit, nil)

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

  @spec assert_non_nil_timestamps!(Pad.ref(), [Buffer.t()], Pad.timestamp_demand_unit()) ::
          :ok | no_return()
  def assert_non_nil_timestamps!(_pad_ref, buffers, unit) when is_timestamp_unit(unit) do
    Enum.each(buffers, fn buffer -> get_timestamp!(buffer, unit, nil) end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_split_buffers(:buffers, buffers, %{demand: count}),
    do: Enum.split(buffers, count)

  defp do_split_buffers(:bytes, buffers, %{demand: count}),
    do: do_split_bytes(buffers, count, [])

  defp do_split_buffers(unit, buffers, ctx) when is_timestamp_unit(unit),
    do: do_split_timestamp_buffers(unit, buffers, ctx)

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

  defp do_split_timestamp_buffers(unit, buffers, ctx) do
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
          get_timestamp!(last_consumed, unit, pad_ref) -
            get_timestamp!(first_consumed, unit, pad_ref) >= demand_timestamp ->
        Membrane.Logger.warning("""
        Demanded #{timestamp_name(unit)} should be greater than the elapsed #{timestamp_name(unit)} \
        since the first consumed buffer. Got :demand of #{demand_timestamp}, while the elapsed \
        #{timestamp_name(unit)} equals \
        #{get_timestamp!(last_consumed, unit, pad_ref) - get_timestamp!(first_consumed, unit, pad_ref)}. \
        Demanding a #{timestamp_name(unit)} that is not greater than the elapsed one \
        won't result in handling any further buffers, until the element demands a #{timestamp_name(unit)} \
        greater than the elapsed one. \
        """)

        {[], buffers}

      is_nil(first_consumed) and buffers == [] ->
        {[], buffers}

      is_nil(first_consumed) ->
        offset = List.first(buffers) |> get_timestamp!(unit, pad_ref)
        split_timestamp_recursion(unit, buffers, [], ctx, offset)

      true ->
        offset = get_timestamp!(first_consumed, unit, pad_ref)
        split_timestamp_recursion(unit, buffers, [], ctx, offset)
    end
  end

  defp split_timestamp_recursion(unit, [buffer | rest], acc, ctx, offset) do
    %{demand: demand_timestamp, pad_ref: pad_ref} = ctx
    acc = [buffer | acc]
    buffer_timestamp = get_timestamp!(buffer, unit, pad_ref)

    if buffer_timestamp - offset >= demand_timestamp do
      {Enum.reverse(acc), rest}
    else
      split_timestamp_recursion(unit, rest, acc, ctx, offset)
    end
  end

  defp split_timestamp_recursion(_unit, [], acc, _ctx, _offset) do
    {Enum.reverse(acc), []}
  end
end
