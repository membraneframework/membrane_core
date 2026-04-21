defmodule Membrane.Buffer.Metric do
  @moduledoc """
  Specifies the type for demand units.

  > #### Deprecated behaviour {: .warning}
  > The callbacks defined here are deprecated. The metric functionality has been moved
  > to the internal API of the Membrane Framework.
  """

  alias Membrane.Buffer

  @callback buffer_size_approximation() :: pos_integer

  @callback buffers_size([Buffer.t()]) ::
              {:ok, non_neg_integer()} | {:error, reason :: atom()}

  @callback split_buffers(
              [Buffer.t()],
              non_neg_integer | Membrane.Time.t(),
              first_consumed_buffer :: Buffer.t() | nil,
              last_consumed_buffer :: Buffer.t() | nil
            ) :: {[Buffer.t()], [Buffer.t()]}

  @callback init_manual_demand_size() :: non_neg_integer() | Membrane.Time.t()

  @callback reduce_demand(
              demand :: non_neg_integer() | Membrane.Time.t(),
              consumed_size :: non_neg_integer() | nil
            ) :: non_neg_integer() | Membrane.Time.t()
end
