defmodule Membrane.Helpers.Time do
  @doc """
  Returns internal Erlang VM clock resolution.

  It will return integer that tells how many "ticks" the VM is handling
  within a second.
  """
  @spec ticks_per_sec() :: non_neg_integer
  def ticks_per_sec do
    :erlang.convert_time_unit(1, :seconds, :native)
  end
end
