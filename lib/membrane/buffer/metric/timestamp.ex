for {timestamp_type, module_suffix} <- [pts: PTS, dts: DTS, dts_or_pts: DTSOrPTS] do
  module_name = Module.concat(Membrane.Buffer.Metric.Timestamp, module_suffix)

  defmodule module_name do
    @moduledoc (case timestamp_type do
                  :pts ->
                    """
                    Implements `Membrane.Buffer.Metric` for PTS-based (Presentation Timestamp) demand.

                    Used when an input pad's `demand_unit` is set to `{:timestamp, :pts}`.
                    All buffers must have `:pts` set to a non-`nil` value.
                    """

                  :dts ->
                    """
                    Implements `Membrane.Buffer.Metric` for DTS-based (Decode Timestamp) demand.

                    Used when an input pad's `demand_unit` is set to `{:timestamp, :dts}`.
                    All buffers must have `:dts` set to a non-`nil` value.
                    """

                  :dts_or_pts ->
                    """
                    Implements `Membrane.Buffer.Metric` for timestamp-based demand using `buffer.dts || buffer.pts`.

                    Used when an input pad's `demand_unit` is set to `:timestamp` or `{:timestamp, :dts_or_pts}`.
                    All buffers must have at least one of `:dts` or `:pts` set to a non-`nil` value.
                    """
                end)

    @behaviour Membrane.Buffer.Metric
    @behaviour Membrane.Buffer.Metric.TimestampMetric

    alias Membrane.Buffer
    alias Membrane.Buffer.Metric
    alias Membrane.Buffer.Metric.TimestampMetric

    require Membrane.Logger

    @initial_manual_demand_size_value -1

    @impl Metric
    def buffer_size_approximation, do: 1

    @impl Metric
    def buffers_size(_buffers), do: {:error, :operation_not_supported}

    @impl Metric
    def init_manual_demand_size_value(), do: @initial_manual_demand_size_value

    @impl Metric
    def split_buffers(
          buffers,
          @initial_manual_demand_size_value,
          _first_consumed_buffer,
          _last_consumed_buffer
        ) do
      {[], buffers}
    end

    @impl Metric
    def split_buffers(buffers, demand_timestamp, first_consumed_buffer, last_consumed_buffer) do
      with {:ok, first_consumed_timestamp} <- get_timestamp(first_consumed_buffer),
           {:ok, last_consumed_timestamp}
           when last_consumed_timestamp - first_consumed_timestamp >= demand_timestamp <-
             get_timestamp(last_consumed_buffer) do
        Membrane.Logger.warning("""
        Demanded #{timestamp_name()} should be greater than the elapsed #{timestamp_name()} \
        since the first consumed buffer. Got :demand of #{demand_timestamp}, while the elapsed \
        #{timestamp_name()} equals #{last_consumed_timestamp - first_consumed_timestamp}. \
        Demanding a #{timestamp_name()} that is not greater than the elapsed one \
        won't result in handling any further buffers, until the element demands a #{timestamp_name()} \
        greater than the elapsed one. \
        """)

        {[], buffers}
      else
        _other when is_nil(first_consumed_buffer) and buffers == [] ->
          {[], []}

        _other when is_nil(first_consumed_buffer) ->
          {:ok, offset} = List.first(buffers) |> get_timestamp()
          split_buffers_recursion(buffers, [], demand_timestamp, offset)

        _other ->
          {:ok, offset} = get_timestamp(first_consumed_buffer)
          split_buffers_recursion(buffers, [], demand_timestamp, offset)
      end
    end

    @impl Metric
    def generate_metric_specific_warnings([]), do: :ok

    def generate_metric_specific_warnings(buffers) do
      [first | rest] = buffers

      _last =
        rest
        |> Enum.reduce(first, fn curr_buffer, prev_buffer ->
          with {:ok, curr_timestamp} <- get_timestamp(curr_buffer),
               {:ok, prev_timestamp} when curr_timestamp < prev_timestamp <-
                 get_timestamp(prev_buffer) do
            Membrane.Logger.warning("""
            Received buffers with non-monotonic #{timestamp_name()}s. \
            Current buffer's #{timestamp_name()} is #{curr_timestamp}, \
            while the previous buffer's #{timestamp_name()} is #{prev_timestamp}. \
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

    @impl Metric
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
      :pts ->
        defp get_timestamp(%Buffer{pts: pts}), do: {:ok, pts}

        @impl TimestampMetric
        def nil_timestamp?(%Buffer{pts: nil}), do: true
        def nil_timestamp?(%Buffer{}), do: false

        @impl TimestampMetric
        def timestamp_name(), do: "PTS"

      :dts ->
        defp get_timestamp(%Buffer{dts: dts}), do: {:ok, dts}

        @impl TimestampMetric
        def nil_timestamp?(%Buffer{dts: nil}), do: true
        def nil_timestamp?(%Buffer{}), do: false

        @impl TimestampMetric
        def timestamp_name(), do: "DTS"

      :dts_or_pts ->
        defp get_timestamp(buffer), do: {:ok, Buffer.get_dts_or_pts(buffer)}

        @impl TimestampMetric
        def nil_timestamp?(buffer), do: is_nil(Buffer.get_dts_or_pts(buffer))

        @impl TimestampMetric
        def timestamp_name(), do: "<DTS || PTS>"
    end
  end
end
