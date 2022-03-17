defmodule Membrane.Support.Sync.Helper do
  @moduledoc false

  @timeout 500

  @spec receive_ticks(non_neg_integer()) :: non_neg_integer()
  def receive_ticks(amount \\ 0) do
    receive do
      :tick -> receive_ticks(amount + 1)
    after
      @timeout -> amount
    end
  end
end
