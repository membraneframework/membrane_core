defmodule Membrane.Buffer do
  @moduledoc """
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

  @type payload_t :: bitstring
  @type caps_t    :: map
  @type origin_t  :: map

  @type t :: %Membrane.Buffer{
    caps: caps_t,
    payload: payload_t,
    origin: origin_t
  }

  defstruct \
    caps: nil,
    payload: nil,
    origin: nil
end
