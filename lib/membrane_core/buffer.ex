defmodule Membrane.Buffer do
  @moduledoc """
  Structure representing a single chunk of data that flows between elements.

  It is just a wrapper around bitstring so there can be some metadata attached
  to it.

  Each buffer:

  - must contain payload,
  - may contain caps describing format of the payload.

  If caps are nil, it means that payload has unknown format.
  """

  @type payload_t :: bitstring
  @type caps_t    :: map

  @type t :: %Membrane.Buffer{
    caps: caps_t,
    payload: payload_t,
  }

  defstruct \
    caps: nil,
    payload: nil
end
