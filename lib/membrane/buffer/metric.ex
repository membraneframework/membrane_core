defmodule Membrane.Buffer.Metric do
  @moduledoc """
  Specifies API for metrics that analyze data in terms of a given unit
  """

  alias Membrane.Buffer
  alias __MODULE__
  alias __MODULE__.Timestamp.{DTS, DTSOrPTS, PTS}

  @type unit :: :buffers | :bytes | :timestamp | {:timestamp, :pts | :dts | :dts_or_pts}
  @type t() :: Metric.Count | Metric.ByteSize | PTS | DTS | DTSOrPTS

  @callback buffer_size_approximation() :: pos_integer

  @callback buffers_size([%Buffer{}] | []) ::
              {:ok, non_neg_integer()} | {:error, reason :: atom()}

  @callback split_buffers(
              [%Buffer{}] | [],
              non_neg_integer | Membrane.Time.t(),
              first_consumed_buffer :: Buffer.t() | nil,
              last_consumed_buffer :: Buffer.t() | nil
            ) :: {[%Buffer{}] | [], [%Buffer{}] | []}

  @callback init_manual_demand_size_value() :: non_neg_integer() | Membrane.Time.t()

  @callback generate_metric_specific_warnings([Buffer.t()]) :: :ok

  @doc """
  Updates the remaining demand after consuming buffers.

  For count/byte metrics, subtracts `consumed_size` from `demand`.
  For timestamp metrics, the demand is a duration that does not change as buffers are consumed —
  the recursion instead terminates when `split_buffers/4` signals that the demand is satisfied.
  """
  @callback reduce_demand(
              demand :: non_neg_integer() | Membrane.Time.t(),
              consumed_size :: non_neg_integer() | nil
            ) :: non_neg_integer() | Membrane.Time.t()

  @spec from_unit(unit()) :: t()
  def from_unit(:buffers), do: Metric.Count
  def from_unit(:bytes), do: Metric.ByteSize
  def from_unit(:timestamp), do: DTSOrPTS
  def from_unit({:timestamp, :pts}), do: PTS
  def from_unit({:timestamp, :dts}), do: DTS
  def from_unit({:timestamp, :dts_or_pts}), do: DTSOrPTS
end
