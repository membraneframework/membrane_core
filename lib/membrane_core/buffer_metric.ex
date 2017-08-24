defmodule Membrane.Buffer.Metric do
  alias Membrane.Buffer
  alias __MODULE__

  @callback pullbuffer_preferred_size() :: pos_integer

  @callback buffers_size([%Buffer{}] | []) :: non_neg_integer

  @callback split_buffers([%Buffer{}] | [], non_neg_integer) ::
    {[%Buffer{}] | [], [%Buffer{}] | []}

  def from_unit(:buffers), do: Metric.Count
  def from_unit(:bytes), do: Metric.ByteSize

end
