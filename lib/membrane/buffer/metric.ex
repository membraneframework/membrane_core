defmodule Membrane.Buffer.Metric do
  @moduledoc """
  Specifies the type for demand units.

  > #### Deprecated behaviour {: .warning}
  > The callbacks defined here are deprecated. The metric functionality has been moved
  > to the internal API of the Membrane Framework.
  """

  alias Membrane.Buffer
  alias __MODULE__

  @type unit :: :buffers | :bytes

  @callback buffer_size_approximation() :: pos_integer

  @callback buffers_size([Buffer.t()]) :: non_neg_integer

  @callback split_buffers([Buffer.t()], non_neg_integer) ::
              {[Buffer.t()], [Buffer.t()]}

  @spec from_unit(unit()) :: module()
  def from_unit(:buffers), do: Metric.Count
  def from_unit(:bytes), do: Metric.ByteSize
end
