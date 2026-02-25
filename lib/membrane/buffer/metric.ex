defmodule Membrane.Buffer.Metric do
  @moduledoc """
  Specifies API for metrics that analyze data in terms of a given unit
  """

  alias Membrane.Buffer
  alias __MODULE__

  @type unit :: :buffers | :bytes | {:timestamp, :pts | :dts | :dts_or_pts}

  @callback buffer_size_approximation() :: pos_integer

  @callback buffers_size([%Buffer{}] | []) ::
              {:ok, non_neg_integer()} | {:error, reason :: atom()}

  @callback split_buffers(
              [%Buffer{}] | [],
              non_neg_integer | Membrane.Time.t(),
              last_buffer_metric_value :: term()
            ) :: {[%Buffer{}] | [], [%Buffer{}] | []}

  @callback get_metric_value(%Buffer{}) :: term()

  @spec from_unit(unit()) :: module()
  def from_unit(:buffers), do: Metric.Count
  def from_unit(:bytes), do: Metric.ByteSize
  def from_unit({:timestamp, :pts}), do: Metric.Timestamp.PTS
  def from_unit({:timestamp, :dts}), do: Metric.Timestamp.DTS
  def from_unit({:timestamp, :dts_or_pts}), do: Metric.Timestamp.DTSOrPTS
end
