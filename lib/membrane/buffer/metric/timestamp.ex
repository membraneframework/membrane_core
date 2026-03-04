for {timestamp_type, module_suffix} <- [pts: PTS, dts: DTS, dts_or_pts: DTSOrPTS] do
  module_name = Module.concat(Membrane.Buffer.Metric.Timestamp, module_suffix)

  defmodule module_name do
    @moduledoc """
    todo
    """

    require Membrane.Logger
    alias Membrane.Buffer

    @behaviour Membrane.Buffer.Metric

    @initial_manual_demand_size_value -1

    @impl true
    def buffer_size_approximation, do: 1

    @impl true
    def buffers_size(_buffers), do: {:error, :operation_not_supported}

    @impl true
    def init_manual_demand_size_value(), do: @initial_manual_demand_size_value

    @impl true
    def split_buffers(
          buffers,
          @initial_manual_demand_size_value,
          _first_consumed_buffer,
          _last_consumed_buffer
        ) do
      {[], buffers}
    end

    @impl true
    def split_buffers(buffers, demand_timestamp, first_consumed_buffer, last_consumed_buffer) do
      with {:ok, first_consumed_timestamp} <- get_timestamp(first_consumed_buffer),
           {:ok, last_consumed_timestamp}
           when last_consumed_timestamp - first_consumed_timestamp >= demand_timestamp <-
             get_timestamp(last_consumed_buffer) do
        Membrane.Logger.warning("""
        Demanded timestamp should greater be than the last consumed timestamp. Got :demand with timestamp \
        #{demand_timestamp}, while the last consumed #{inspected_timestamp_type()} equals \
        #{last_consumed_timestamp}. Demanding timestamp that is not greater than the last consumed one \
        won't result in handling any further buffers, until the Element demands a timestamp greater than \
        the last consumed one. \
        """)

        {[], buffers}
      else
        _timestamp when first_consumed_buffer == nil and buffers != [] ->
          {:ok, first_buffer_timestamp} = List.first(buffers) |> get_timestamp()
          split_buffers_recursion(buffers, [], demand_timestamp, first_buffer_timestamp)

        _timestamp ->
          {:ok, first_buffer_timestamp} = get_timestamp(first_consumed_buffer)
          split_buffers_recursion(buffers, [], demand_timestamp, first_buffer_timestamp)
      end

      # |> IO.inspect(
      #   label:
      #     "SPLIT_BUFFERS RESULT FOR DEMAND OF TIMESTAMP #{demand_timestamp}, FIRST CONSUMED #{inspect(first_consumed_buffer)}, LAST CONSUMED #{inspect(last_consumed_buffer)}"
      # )
    end

    @impl true
    def generate_metric_specific_warnings([]), do: :ok

    def generate_metric_specific_warnings(buffers) do
      [first | rest] = buffers

      rest
      |> Enum.reduce(first, fn curr_buffer, prev_buffer ->
        with {:ok, curr_timestamp} <- get_timestamp(curr_buffer),
             {:ok, prev_timestamp} when curr_timestamp < prev_timestamp <-
               get_timestamp(prev_buffer) do
          if curr_timestamp < prev_timestamp do
            Membrane.Logger.warning("""
            Received buffers with non-monotonic #{inspected_timestamp_type()}s. Current buffer's timestamp is \
            #{curr_timestamp}, while the previous buffer's timestamp is #{prev_timestamp}. This may lead to \
            unexpected behavior in Elements that rely on monotonicity of timestamps, such as decoders or \
            muxers.
            """)
          end

          curr_buffer
        else
          _ -> curr_buffer
        end
      end)
    end

    defp split_buffers_recursion([buffer | rest], buffers_to_consume, demand_timestamp, offset) do
      buffers_to_consume = [buffer | buffers_to_consume]
      {:ok, buffer_timestamp} = get_timestamp(buffer)

      # IO.inspect({buffer_timestamp, offset, demand_timestamp}, label: "A B C")

      if buffer_timestamp - offset >= demand_timestamp,
        do: {Enum.reverse(buffers_to_consume), rest},
        else: split_buffers_recursion(rest, buffers_to_consume, demand_timestamp, offset)
    end

    defp split_buffers_recursion([], buffers_to_consume, _demand_timestamp, _offset),
      do: {Enum.reverse(buffers_to_consume), []}

    defp get_timestamp(nil), do: :error

    case timestamp_type do
      :pts -> defp get_timestamp(%Buffer{pts: pts}), do: {:ok, pts}
      :dts -> defp get_timestamp(%Buffer{dts: dts}), do: {:ok, dts}
      :dts_or_pts -> defp get_timestamp(buffer), do: {:ok, Buffer.get_dts_or_pts(buffer)}
    end

    case timestamp_type do
      :pts -> defp inspected_timestamp_type(), do: "PTS"
      :dts -> defp inspected_timestamp_type(), do: "DTS"
      :dts_or_pts -> defp inspected_timestamp_type(), do: "<DTS or PTS>"
    end
  end
end
