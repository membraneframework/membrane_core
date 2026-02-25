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
    def split_buffers(buffers, demand_timestamp, last_consumed_timestamp) do
      if demand_timestamp <= last_consumed_timestamp do
        inspected_timestamp_type =
          unquote(timestamp_type)
          |> Atom.to_string()
          |> String.replace("_", " ")

        Membrane.Logger.warning("""
        Demanded timestamp should greater than the last consumed timestamp. Got :demand with timestamp \
        #{demand_timestamp}, while the last consumed #{inspected_timestamp_type} equals \
        #{last_consumed_timestamp}. Demanding timestamp that is not greater than the last consumed one \
        won't result in handling any further buffers, until the Element demands a timestamp greater than \
        the last consumed one. \
        """)

        {[], buffers}
      else
        split_buffers_recursion(buffers, [], demand_timestamp)
      end
    end

    defp split_buffers_recursion([buffer | rest], buffers_to_consume, timestamp) do
      buffers_to_consume = [buffer | buffers_to_consume]

      if get_metric_value(buffer) >= timestamp,
        do: {Enum.reverse(buffers_to_consume), rest},
        else: split_buffers_recursion(rest, buffers_to_consume, timestamp)
    end

    defp split_buffers_recursion([], buffers_to_consume, _timestamp),
      do: {Enum.reverse(buffers_to_consume), []}

    @impl true
    case timestamp_type do
      :pts -> def get_metric_value(%Buffer{pts: pts}), do: pts
      :dts -> def get_metric_value(%Buffer{dts: dts}), do: dts
      :dts_or_pts -> def get_metric_value(buffer), do: Buffer.get_dts_or_pts(buffer)
    end
  end
end
