defmodule Membrane.Buffer.Metric.TimestampMetric do
  @moduledoc false

  alias Membrane.Buffer

  @doc """
  Returns `true` if the buffer is missing the timestamp field required by this metric.
  """
  @callback nil_timestamp?(Buffer.t()) :: boolean()

  @doc """
  Returns a human-readable name for the timestamp field used by this metric,
  e.g. `"PTS"`, `"DTS"`, or `"DTS or PTS"`.
  """
  @callback timestamp_name() :: String.t()
end
