defmodule Membrane.Buffer do
  @moduledoc """
  Structure representing a single chunk of data that flows between elements.

  For now, it is just a wrapper around bitstring with optionally some metadata
  attached to it, but in future releases we plan to support different payload
  types.
  """

  alias __MODULE__

  @type payload_t :: bitstring
  @type metadata_t :: map

  @type t :: %Buffer{
          payload: payload_t,
          metadata: metadata_t
        }

  @enforce_keys [:payload]
  defstruct payload: nil,
            metadata: Map.new()

  @doc """
  Converts buffer/buffers to the format in which they can be logged with
  `Membrane.Log`.
  """
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
