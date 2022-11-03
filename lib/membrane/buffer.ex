defmodule Membrane.Buffer do
  @moduledoc """
  Structure representing a single chunk of data that flows between elements.

  For now, it is just a wrapper around bitstring with optionally some metadata
  attached to it, but in future releases we plan to support different payload
  types.
  """

  alias __MODULE__
  alias Membrane.Payload
  alias Membrane.Time

  @type metadata_t :: map

  @type t :: %Buffer{
          pts: Time.t() | nil,
          dts: Time.t() | nil,
          payload: Payload.t(),
          metadata: metadata_t
        }

  @enforce_keys [:payload]
  defstruct @enforce_keys ++ [pts: nil, dts: nil, metadata: Map.new()]

  @doc """
  Returns `t:Membrane.Buffer.t/0` `:dts` if available or `:pts` if `:dts` is not set.
  If none of them is set `nil` is returned.
  """
  @spec get_dts_or_pts(__MODULE__.t()) :: Time.t() | nil
  def get_dts_or_pts(buffer) do
    buffer.dts || buffer.pts
  end
end
