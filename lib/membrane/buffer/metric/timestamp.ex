defmodule Membrane.Buffer.Metric.Timestamp do
  @moduledoc false

  alias Membrane.Buffer
  alias Membrane.Pad
  require Membrane.Logger

  @doc """
  Returns the timestamp value used for demand calculation for the given buffer.
  """
  @callback get_timestamp(Buffer.t()) :: Membrane.Time.t()

  @doc """
  Returns a human-readable name for the timestamp field used by this metric.
  """
  @callback timestamp_name() :: String.t()

  defguard is_timestamp_metric?(module)
           when module in [
                  __MODULE__.PTS,
                  __MODULE__.DTS,
                  __MODULE__.DTSorPTS
                ]

  defmacro __using__(_opts) do
    quote do
      alias Membrane.Buffer.Metric
      alias Membrane.Buffer.Metric.Timestamp.Utils

      @init_manual_demand_size -1

      @behaviour Metric
      @behaviour Metric.Timestamp

      @impl Metric
      def buffer_size_approximation, do: 1

      @impl Metric
      def buffers_size(_buffers), do: {:error, :operation_not_supported}

      @impl Metric
      def init_manual_demand_size(), do: @init_manual_demand_size

      @impl Metric
      def split_buffers(buffers, demand_timestamp, first_consumed_buffer, last_consumed_buffer) do
        Utils.split_buffers(
          buffers,
          demand_timestamp,
          first_consumed_buffer,
          last_consumed_buffer,
          unquote(__CALLER__.module)
        )
      end

      @impl Metric
      def reduce_demand(demand, _consumed), do: demand
    end
  end

  @spec generate_metric_specific_warnings(Pad.ref(), [Buffer.t()], module()) :: :ok
  def generate_metric_specific_warnings(_pad_ref, [], _timestamp_metric), do: :ok

  def generate_metric_specific_warnings(pad_ref, buffers, timestamp_metric) do
    [first | rest] = buffers

    _last =
      rest
      |> Enum.reduce(first, fn
        curr_buffer, nil ->
          curr_buffer

        curr_buffer, prev_buffer ->
          prev_timestamp = timestamp_metric.get_timestamp(prev_buffer)
          curr_timestamp = timestamp_metric.get_timestamp(curr_buffer)

          if curr_timestamp < prev_timestamp do
            Membrane.Logger.warning("""
            Received buffers with non-monotonic #{timestamp_metric.timestamp_name()}s. \
            Current buffer's #{timestamp_metric.timestamp_name()} is #{curr_timestamp}, \
            while the previous buffer's #{timestamp_metric.timestamp_name()} is #{prev_timestamp}. \
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

  @spec assert_non_nil_timestamps!(Pad.ref(), [Buffer.t()], module()) :: :ok | no_return()
  def assert_non_nil_timestamps!(pad_ref, buffers, timestamp_metric) do
    buffers
    |> Enum.each(fn buffer ->
      if timestamp_metric.get_timestamp(buffer) == nil do
        raise """
        All buffers must have a non-nil #{timestamp_metric.timestamp_name()} when using \
        #{timestamp_metric} as a demand unit for input pads with manual flow control.
        Pad reference: #{inspect(pad_ref)}
        Buffer: #{inspect(buffer)}
        """
      end
    end)
  end
end
