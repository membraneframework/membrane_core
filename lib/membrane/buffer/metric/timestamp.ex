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
        Demanded #{inspected_timestamp_type()} should be greater than the elapsed #{inspected_timestamp_type()} \
        since the first consumed buffer. Got :demand of #{demand_timestamp}, while the elapsed \
        #{inspected_timestamp_type()} equals #{last_consumed_timestamp - first_consumed_timestamp}. \
        Demanding a #{inspected_timestamp_type()} that is not greater than the elapsed one \
        won't result in handling any further buffers, until the element demands a #{inspected_timestamp_type()} \
        greater than the elapsed one. \
        """)

        {[], buffers}
      else
        _other when is_nil(first_consumed_buffer) ->
          {:ok, offset} = List.first(buffers) |> get_timestamp()
          split_buffers_recursion(buffers, [], demand_timestamp, offset)

        _other ->
          {:ok, offset} = get_timestamp(first_consumed_buffer)
          split_buffers_recursion(buffers, [], demand_timestamp, offset)
      end
    end

    @impl true
    def generate_metric_specific_warnings([]), do: :ok

    def generate_metric_specific_warnings(buffers) do
      [first | rest] = buffers

      Enum.reduce(rest, first, fn curr_buffer, prev_buffer ->
        with {:ok, curr_timestamp} <- get_timestamp(curr_buffer),
             {:ok, prev_timestamp} when curr_timestamp < prev_timestamp <-
               get_timestamp(prev_buffer) do
          Membrane.Logger.warning("""
          Received buffers with non-monotonic #{inspected_timestamp_type()}s. \
          Current buffer's #{inspected_timestamp_type()} is #{curr_timestamp}, \
          while the previous buffer's #{inspected_timestamp_type()} is #{prev_timestamp}. \
          This may lead to unexpected behavior in elements that have input pad with flow \
          control set to `:manual` and demand unit set to `:timestamp`, `{:timestamp, :dts}` \
          `{:timestamp, :pts}` or `{:timestamp, :dts_or_pts}`.
          """)

          curr_buffer
        else
          _other -> curr_buffer
        end
      end)

      :ok
    end

    @impl true
    def reduce_demand(demand, _consumed), do: demand

    defp split_buffers_recursion([buffer | rest], buffers_to_consume, demand_timestamp, offset) do
      buffers_to_consume = [buffer | buffers_to_consume]
      {:ok, buffer_timestamp} = get_timestamp(buffer)

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
