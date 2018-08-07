defprotocol Membrane.Payload do
  @moduledoc """
  This protocol describes actions common to all payload types.

  The most basic payload type is simply a binary for which `#{__MODULE__}`
  is implemented by the Membrane Core.
  """

  @type t :: struct()

  @doc """
  Returns total size of payload in bytes
  """
  @spec size(payload :: t()) :: non_neg_integer()
  def size(payload)

  @doc """
  Splits the payload at given position (1st part has the size equal to `at_pos` argument)
  """
  @spec split_at(payload :: t(), at_pos :: non_neg_integer()) :: {t(), t()}
  def split_at(payload, at_pos)

  @doc """
  Converts payload into binary
  """
  @spec to_binary(t()) :: binary()
  def to_binary(payload)
end

defimpl Membrane.Payload, for: BitString do
  @spec size(payload :: binary()) :: non_neg_integer
  def size(data) when is_binary(data) do
    data |> byte_size()
  end

  @spec split_at(binary(), non_neg_integer) :: {binary(), binary()}
  def split_at(data, 0) do
    {<<>>, data}
  end

  def split_at(data, at_pos) when byte_size(data) <= at_pos do
    {data, <<>>}
  end

  def split_at(data, at_pos) do
    <<part1::binary-size(at_pos), part2::binary>> = data
    {part1, part2}
  end

  @spec to_binary(binary()) :: binary()
  def to_binary(data) when is_binary(data) do
    data
  end
end
