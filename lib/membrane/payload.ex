defprotocol Membrane.Payload do
  @type t :: struct()

  @doc "Returns total size of paload in bytes"
  @spec size(payload :: t()) :: non_neg_integer()
  def size(payload)

  @doc "Splits the payload at given position (1st part has the size equal to `at_pos` argument)"
  @spec split_at(payload :: t(), at_pos :: non_neg_integer()) :: {t(), t()}
  def split_at(payload, at_pos)
end
