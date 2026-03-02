for {timestamp_type, module_suffix} <- [pts: PTS, dts: DTS, dts_or_pts: DTSOrPTS] do
  module_name = Module.concat(Membrane.Buffer.Metric.Timestamp, module_suffix)

  defmodule module_name do
    @moduledoc """
    todo
    """

    require Membrane.Logger
    alias Membrane.Buffer

    @behaviour Membrane.Buffer.Metric

    @impl true
    def buffer_size_approximation, do: 1

    @impl true
    def buffers_size(_buffers), do: {:error, :operation_not_supported}

    @impl true
    def split_buffers(buffers, demand_timestamp, last_consumed_buffer) do
      with {:ok, last_consumed_timestamp} when demand_timestamp <= last_consumed_timestamp <-
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
        _timestamp -> split_buffers_recursion(buffers, [], demand_timestamp)
      end
    end

    defp split_buffers_recursion([buffer | rest], buffers_to_consume, timestamp) do
      buffers_to_consume = [buffer | buffers_to_consume]

      if get_timestamp(buffer) >= timestamp,
        do: {Enum.reverse(buffers_to_consume), rest},
        else: split_buffers_recursion(rest, buffers_to_consume, timestamp)
    end

    defp split_buffers_recursion([], buffers_to_consume, _timestamp),
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
