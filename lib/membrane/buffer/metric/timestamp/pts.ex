defmodule Membrane.Buffer.Metric.Timestamp.PTS do
  @moduledoc """
  Implements `Membrane.Buffer.Metric` for PTS-based (Presentation Timestamp) demand.

  Used when an input pad's `demand_unit` is set to `{:timestamp, :pts}`.
  All buffers must have `:pts` set to a non-`nil` value.
  """
  use Membrane.Buffer.Metric.Timestamp
  alias Membrane.Buffer.Metric

  @impl Metric.Timestamp
  def get_timestamp(%Membrane.Buffer{pts: pts}), do: pts

  @impl Metric.Timestamp
  def timestamp_name(), do: "PTS"
end
