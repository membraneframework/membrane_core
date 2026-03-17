defmodule Membrane.Buffer.Metric.TimestampMetric do
  @moduledoc false

  alias Membrane.Buffer

  @doc """
  Returns `true` if the buffer is missing the timestamp field required by this metric.
  """
  @callback get_timestamp?(Buffer.t()) :: Membrane.Time.t()

  @doc """
  Returns a human-readable name for the timestamp field used by this metric,
  e.g. `"PTS"`, `"DTS"`, or `"DTS or PTS"`.
  """
  @callback timestamp_name() :: String.t()

  defguard is_timestamp_metric?(module)
           when module in [
                  __MODULE__.PTS,
                  __MODULE__.DTS,
                  __MODULE__.DTSOrPTS
                ]
end
