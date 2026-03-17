defmodule Membrane.Buffer.Metric.Timestamp.Utils do
  @moduledoc false

  alias Membrane.Buffer
  require Membrane.Logger

  @spec split_buffers(
          [Buffer.t()],
          Membrane.Time.t(),
          Buffer.t() | nil,
          Buffer.t() | nil,
          module()
        ) :: {[Buffer.t()], [Buffer.t()]}
  def split_buffers(
        buffers,
        demand_timestamp,
        first_consumed_buffer,
        last_consumed_buffer,
        timestamp_metric
      ) do
    cond do
      timestamp_metric.init_manual_demand_size() == demand_timestamp ->
        {[], buffers}

      first_consumed_buffer != nil and last_consumed_buffer != nil and
          timestamp_metric.get_timestamp(last_consumed_buffer) -
            timestamp_metric.get_timestamp(first_consumed_buffer) >= demand_timestamp ->
        Membrane.Logger.warning("""
        Demanded #{timestamp_metric.timestamp_name()} should be greater than the elapsed #{timestamp_metric.timestamp_name()} \
        since the first consumed buffer. Got :demand of #{demand_timestamp}, while the elapsed \
        #{timestamp_metric.timestamp_name()} equals \
        #{timestamp_metric.get_timestamp(last_consumed_buffer) - timestamp_metric.get_timestamp(first_consumed_buffer)}. \
        Demanding a #{timestamp_metric.timestamp_name()} that is not greater than the elapsed one \
        won't result in handling any further buffers, until the element demands a #{timestamp_metric.timestamp_name()} \
        greater than the elapsed one. \
        """)

        {[], buffers}

      is_nil(first_consumed_buffer) and buffers == [] ->
        {[], buffers}

      is_nil(first_consumed_buffer) ->
        offset = List.first(buffers) |> timestamp_metric.get_timestamp()
        split_buffers_recursion(buffers, [], demand_timestamp, offset, timestamp_metric)

      true ->
        offset = timestamp_metric.get_timestamp(first_consumed_buffer)
        split_buffers_recursion(buffers, [], demand_timestamp, offset, timestamp_metric)
    end
  end

  defp split_buffers_recursion(
         [buffer | rest],
         buffers_to_consume,
         demand_timestamp,
         offset,
         timestamp_metric
       ) do
    buffers_to_consume = [buffer | buffers_to_consume]
    buffer_timestamp = timestamp_metric.get_timestamp(buffer)

    if buffer_timestamp - offset >= demand_timestamp do
      {Enum.reverse(buffers_to_consume), rest}
    else
      split_buffers_recursion(
        rest,
        buffers_to_consume,
        demand_timestamp,
        offset,
        timestamp_metric
      )
    end
  end

  defp split_buffers_recursion(
         [],
         buffers_to_consume,
         _demand_timestamp,
         _offset,
         _timestamp_metric
       ),
       do: {Enum.reverse(buffers_to_consume), []}
end
