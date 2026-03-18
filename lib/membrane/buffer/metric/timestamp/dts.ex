defmodule Membrane.Buffer.Metric.Timestamp.DTS do
  @moduledoc """
  Implements `Membrane.Buffer.Metric` for DTS-based (Decoded Timestamp) demand.

  Used when an input pad's `demand_unit` is set to `{:timestamp, :dts}`.
  All buffers must have `:dts` set to a non-`nil` value.
  """

  use Membrane.Buffer.Metric.Timestamp
  alias Membrane.Buffer.Metric

  @impl Metric.Timestamp
  def get_timestamp(%Membrane.Buffer{dts: dts}), do: dts

  @impl Metric.Timestamp
  def timestamp_name(), do: "DTS"
end
