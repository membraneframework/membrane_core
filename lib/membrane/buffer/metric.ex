defmodule Membrane.Buffer.Metric do
  @moduledoc """
  Specifies the type for demand units.

  > #### Deprecated behaviour {: .warning}
  > The callbacks defined here are deprecated. Use `Membrane.Core.Metric` functions
  > (which dispatch on `demand_unit`) instead of implementing this behaviour.
  """

  alias Membrane.Buffer

  @type unit :: :buffers | :bytes | :timestamp | {:timestamp, :pts | :dts | :dts_or_pts}

  @callback buffer_size_approximation() :: pos_integer

  @callback buffers_size([%Buffer{}] | []) ::
              {:ok, non_neg_integer()} | {:error, reason :: atom()}

  @callback split_buffers(
              [%Buffer{}] | [],
              non_neg_integer | Membrane.Time.t(),
              first_consumed_buffer :: Buffer.t() | nil,
              last_consumed_buffer :: Buffer.t() | nil
            ) :: {[%Buffer{}] | [], [%Buffer{}] | []}

  @callback init_manual_demand_size() :: non_neg_integer() | Membrane.Time.t()

  @callback reduce_demand(
              demand :: non_neg_integer() | Membrane.Time.t(),
              consumed_size :: non_neg_integer() | nil
            ) :: non_neg_integer() | Membrane.Time.t()
end
