defmodule Membrane.Buffer.Metric.Count do
  alias Membrane.Buffer
  @behaviour Buffer.Metric

  def pullbuffer_preferred_size, do: 10

  def buffers_size(buffers), do: length(buffers)

  def split_buffers(buffers, count), do: buffers |> Enum.split(count)
end
