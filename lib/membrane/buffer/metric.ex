defmodule Membrane.Buffer.Metric do
  @moduledoc """
  Specifies API for metrics that analyze data in terms of a given unit
  """

  alias Membrane.Buffer
  alias __MODULE__

  @type unit_t :: :buffers | :bytes

  @callback buffer_size_approximation() :: pos_integer

  @callback buffers_size([%Buffer{}] | []) :: non_neg_integer

  @callback split_buffers([%Buffer{}] | [], non_neg_integer) ::
              {[%Buffer{}] | [], [%Buffer{}] | []}

  @spec from_unit(unit_t()) :: module()
  def from_unit(:buffers), do: Metric.Count
  def from_unit(:bytes), do: Metric.ByteSize
end
