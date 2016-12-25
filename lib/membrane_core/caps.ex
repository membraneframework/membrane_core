defmodule Membrane.Caps do
  @type t :: struct


  @doc """
  Performs intersection of given lists of caps.

  Returns a list of caps that are present in both lists.
  """
  @spec intersect([t], [t]) :: [] | [t]
  def intersect(caps1, caps2) do
    # TODO
  end
end
