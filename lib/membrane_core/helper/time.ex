defmodule Membrane.Helper.Time do
  @moduledoc """
  Module containing helper functions for handling time.

  They often map to the one-liner erlang calls but keeping them in the module
  eases mocking in the specs.
  """


  @doc """
  Returns internal Erlang VM clock resolution.

  It will return integer that tells how many "ticks" the VM is handling
  within a second.
  """
  @spec resolution() :: pos_integer
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
