defmodule Membrane.Buffer.Metric.Timestamp.DTSorPTS do
  @moduledoc """
  Implements `Membrane.Buffer.Metric` for <DTS || PTS> demand.

  Used when an input pad's `demand_unit` is set to `{:timestamp, :dts_or_pts}` ot `:timestamp`.
  All buffers must have `:dts` or `:pts` set to a non-`nil` value.
  """

  use Membrane.Buffer.Metric.Timestamp
  alias Membrane.Buffer.Metric

  @impl Metric.Timestamp
  def get_timestamp(buffer), do: Membrane.Buffer.get_dts_or_pts(buffer)

  @impl Metric.Timestamp
  def timestamp_name(), do: "<DTS || PTS>"
end
