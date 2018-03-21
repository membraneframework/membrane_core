defmodule Membrane.Buffer do
  @moduledoc """
  Structure representing a single chunk of data that flows between elements.

  It is just a wrapper around bitstring with optionally some metadata
  attached to it.

  Each buffer:

  - must contain payload.
  """

  alias __MODULE__

  @type payload_t :: bitstring

  @type t :: %Buffer{
          payload: payload_t,
          metadata: Buffer.Metadata.t()
        }

  defstruct payload: nil,
            metadata: Buffer.Metadata.new()

  def print(%Buffer{metadata: metadata, payload: payload}),
    do: [
      "%Membrane.Buffer{metadata: ",
      inspect(metadata),
      ", payload: ",
      {:binary, payload},
      "}"
    ]

  def print(buffers), do: buffers |> Enum.map(&print/1)
end
