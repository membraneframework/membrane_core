defmodule Membrane.Helper.Time do
  @doc """
  Returns internal Erlang VM clock resolution.

  It will return integer that tells how many "ticks" the VM is handling
  within a second.
  """
  @spec resolution() :: non_neg_integer
  def resolution do
    :erlang.convert_time_unit(1, :seconds, :native)
  end


  @doc """
  Returns current monotonic time.

  It is a wrapper around `:erlang.monotonic_time/0` made mostly for purpose
  of mocking such calls in specs.
  """
  @spec monotonic_time() :: integer
  def monotonic_time do
    :erlang.monotonic_time()
  end
end
