defmodule Membrane.Buffer do
  @moduledoc """
  Structure representing a single chunk of data that flows between elements.

  It is just a wrapper around bitstring with optionally some metadata
  attached to it.

  Each buffer:

  - must contain payload.
  """

  @type payload_t :: bitstring

  @type t :: %Membrane.Buffer{
    payload: payload_t,
    metadata: Membrane.Buffer.Metadata.t,
  }

  defstruct \
    payload: nil,
    metadata: Membrane.Buffer.Metadata.new
end
