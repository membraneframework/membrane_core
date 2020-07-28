defprotocol Membrane.Payload do
  @moduledoc """
  This protocol describes actions common to all payload types.

  The most basic payload type is simply a binary for which `#{__MODULE__}`
  is implemented by the Membrane Core.
  """

  defmodule Behaviour do
    @moduledoc """
    Behaviour that should be implemented by every module that has
    `Membrane.Payload` protocol implementation.
    """

    @doc """
    Creates an empty payload
    """
    @callback empty() :: Membrane.Payload.t()

    @doc """
    Creates a new payload initialized with the given binary
    """
    @callback new(binary()) :: Membrane.Payload.t()
  end

  @type t :: any()

  @doc """
  Returns total size of payload in bytes
  """
  @spec size(payload :: t()) :: non_neg_integer()
  def size(payload)

  @doc """
  Splits the payload at given position (1st part has the size equal to `at_pos` argument)

  `at_pos` has to be greater than 0 and smaller than the size of payload, otherwise
  an error is raised. This guarantees returned payloads are never empty.
  """
  @spec split_at(payload :: t(), at_pos :: pos_integer()) :: {t(), t()}
  def split_at(payload, at_pos)

  @doc """
  Concatenates the contents of two payloads.
  """
  @spec concat(left :: t(), right :: t()) :: t()
  def concat(left, right)

  @doc """
  Drops first `n` bytes of payload.
  """
  @spec drop(payload :: t(), n :: non_neg_integer()) :: t()
  def drop(payload, n)

  @doc """
  Converts payload into binary
  """
  @spec to_binary(t()) :: binary()
  def to_binary(payload)

  @doc """
  Returns a module responsible for this type of payload
  and implementing `Membrane.Payload.Behaviour`
  """
  @spec module(t()) :: module()
  def module(payload)
end

defmodule Membrane.Payload.Binary do
  @moduledoc """
  `Membrane.Payload.Behaviour` implementation for binary payload.
  Complements `Membrane.Payload` protocol implementation.
  """
  @behaviour Membrane.Payload.Behaviour

  @impl true
  def empty(), do: <<>>

  @impl true
  def new(data) when is_binary(data) do
    data
  end
end

defimpl Membrane.Payload, for: BitString do
  alias Membrane.Payload

  @compile {:inline, module: 1}

  @impl true
  @spec size(payload :: binary()) :: pos_integer
  def size(payload) when is_binary(payload) do
    payload |> byte_size()
  end

  @impl true
  @spec split_at(binary(), pos_integer) :: {binary(), binary()}
  def split_at(payload, at_pos)
      when is_binary(payload) and 0 < at_pos and at_pos < byte_size(payload) do
    <<part1::binary-size(at_pos), part2::binary>> = payload
    {part1, part2}
  end

  @impl true
  @spec concat(left :: binary(), right :: binary()) :: binary()
  def concat(left, right) when is_binary(left) and is_binary(right) do
    left <> right
  end

  @impl true
  @spec drop(payload :: binary(), bytes :: non_neg_integer()) :: binary()
  def drop(payload, bytes) when is_binary(payload) do
    <<_dropped::binary-size(bytes), rest::binary>> = payload
    rest
  end

  @impl true
  @spec to_binary(binary()) :: binary()
  def to_binary(payload) when is_binary(payload) do
    payload
  end

  @impl true
  @spec module(binary()) :: module()
  def module(_payload), do: Payload.Binary
end
