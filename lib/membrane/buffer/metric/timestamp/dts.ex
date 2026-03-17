defmodule Membrane.Buffer.Metric.Timestamp.DTS do
  @moduledoc """
  Implements `Membrane.Buffer.Metric` for DTS-based (Decoded Timestamp) demand.

  Used when an input pad's `demand_unit` is set to `{:timestamp, :dts}`.
  All buffers must have `:dts` set to a non-`nil` value.
  """

  @behaviour Membrane.Buffer.Metric
  @behaviour Membrane.Buffer.Metric.Timestamp

  alias Membrane.Buffer
  alias Membrane.Buffer.Metric
  alias Membrane.Buffer.Metric.Timestamp.Utils

  require Membrane.Logger

  @init_manual_demand_size -1

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
      __MODULE__
    )
  end

  @impl Metric
  def reduce_demand(demand, _consumed), do: demand

  @impl Metric.Timestamp
  def get_timestamp(%Buffer{dts: dts}), do: dts

  @impl Metric.Timestamp
  def timestamp_name(), do: "DTS"
end
