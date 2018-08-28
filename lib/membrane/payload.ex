defprotocol Membrane.Payload do
  @moduledoc """
  This protocol describes actions common to all payload types.

  The most basic payload type is simply a binary for which `#{__MODULE__}`
  is implemented by the Membrane Core.
  """

  defmodule Behaviour do
    @moduledoc """
    Behaviour that should be implemented by every module that has
    `Membrane.Payload` protocol implemetation.
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
  Creates an empty payload of the same type
  """
  @spec empty(payload :: t()) :: t()
  def empty(payload)

  @doc """
  Creates a new payload of the same type initialized with given binary
  """
  @spec new(payload :: t(), binary()) :: t()
  def new(payload, data)

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
  Returns a module defining this type of payload.
  """
  @spec module(t()) :: module()
  def module(payload)
end

defmodule Membrane.Payload.Common do
  @moduledoc """
  Module that should be `use`d in every `Membrane.Payload` protocol implemetation
  """
  defmacro __using__(_) do
    quote do
      alias Membrane.Payload

      @compile {:inline, empty: 0, empty: 1, new: 1, new: 2, module: 1}

      @impl Payload
      def module(_), do: __MODULE__
    end
  end
end

defimpl Membrane.Payload, for: BitString do
  use Membrane.Payload.Common
  @behaviour Payload.Behaviour

  @impl Payload.Behaviour
  def empty(), do: <<>>

  @impl Payload.Behaviour
  def new(data), do: data

  @impl Payload
  def empty(_payload), do: empty()

  @impl Payload
  def new(_payload, data), do: new(data)

  @impl Payload
  @spec size(payload :: binary()) :: pos_integer
  def size(payload) when is_binary(payload) do
    payload |> byte_size()
  end

  @impl Payload
  @spec split_at(binary(), pos_integer) :: {binary(), binary()}
  def split_at(payload, at_pos)
      when is_binary(payload) and 0 < at_pos and at_pos < byte_size(payload) do
    <<part1::binary-size(at_pos), part2::binary>> = payload
    {part1, part2}
  end

  @impl Payload
  @spec concat(left :: binary(), right :: binary()) :: binary()
  def concat(left, right) when is_binary(left) do
    left <> Payload.to_binary(right)
  end

  @impl Payload
  @spec drop(payload :: binary(), bytes :: non_neg_integer()) :: binary()
  def drop(payload, bytes) when is_binary(payload) do
    <<_dropped::binary-size(bytes), rest::binary>> = payload
    rest
  end

  @impl Payload
  @spec to_binary(binary()) :: binary()
  def to_binary(payload) when is_binary(payload) do
    payload
  end
end
