defmodule Membrane.Buffer do
  @doc """
  Structure representing a single chunk of data that flows between elements.

  It is just a wrapper around bitstring so there can be some metadata attached
  to it.

  Each buffer:

  - must contain payload,
  - may contain caps describing format of the payload,
  - may contain information about origin (e.g. IP address that has sent data to us)

  If caps are nil, it means that payload has unknown format.

  If origin is nil, it means that payload has unknown origin.
  """

  @type t :: %Membrane.Buffer{
    caps: %Membrane.Caps{},
    payload: bitstring,
    origin: map
  }

  defstruct \
    caps: nil,
    payload: nil,
    origin: nil
end
