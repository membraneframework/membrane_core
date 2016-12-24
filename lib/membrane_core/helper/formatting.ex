defmodule Membrane.Helper.Formatting do
  @doc """
  Formats IP address.
  """
  @spec ip(:inet.socket_address) :: String.t
  def ip({a,b,c,d}) do
    "#{a}.#{b}.#{c}.#{d}"
  end


  def ip(other) do
    inspect(other)
  end
end
