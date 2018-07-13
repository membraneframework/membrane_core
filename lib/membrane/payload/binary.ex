defmodule Membrane.Payload.Binary do
  @moduledoc """
  Defines default payload type holding an Elixir binary
  """

  @type t :: %__MODULE__{
          data: bitstring()
        }

  @enforce_keys :data
  defstruct [:data]
end

defimpl Membrane.Payload, for: Membrane.Payload.Binary do
  alias Membrane.Payload.Binary

  @spec size(payload :: Binary.t()) :: non_neg_integer
  def size(%Binary{data: data}) do
    data |> byte_size()
  end

  @spec split_at(%Binary{}, non_neg_integer) :: {%Binary{}, %Binary{}}
  def split_at(%Binary{} = b, 0) do
    {%Binary{data: <<>>}, b}
  end

  def split_at(%Binary{data: data} = b, at_pos) when byte_size(data) <= at_pos do
    {b, %Binary{data: <<>>}}
  end

  def split_at(%Binary{data: data}, at_pos) do
    <<part1::binary-size(at_pos), part2::binary>> = data
    {part1, part2}
  end
end
