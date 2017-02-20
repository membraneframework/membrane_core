defmodule Membrane.Buffer do
  @moduledoc """
  Structure representing a single chunk of data that flows between elements.

  It is just a wrapper around bitstring. In the future they might be some
  metadata attached to it.

  Each buffer:

  - must contain payload.
  """

  @type payload_t :: bitstring

  @type t :: %Membrane.Buffer{
    payload: payload_t,
  }

  defstruct \
    payload: nil
end
