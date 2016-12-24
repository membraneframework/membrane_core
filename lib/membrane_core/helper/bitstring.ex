defmodule Membrane.Helper.Bitstring do
  @doc """
  Splits given bitstring into parts of given size, and calls given function
  for each part.

  Passed function has to accept one argument that will be a bitstring and
  return a value. It accumulates result of all function calls.

  Returns `{:ok, {accumulated_result, remaining_bitstring}}`.

  This function is useful for handling buffer's payload if element's logic
  expects to process certain amount of samples in one pass. For example,
  Opus encoder expects to receive particular amount of samples, which total
  duration is equal to the selected frame size duration, but there's no guarantee
  that incoming buffer contains exactly requested amount of samples.

  Please note that size is expressed in bytes, not samples.
  """
  @spec split_map(bitstring, pos_integer, fun) :: {:ok, {[] | [...], bitstring}}
  def split_map(data, size, process_fun) do
    split_map_recurse(data, size, process_fun, [])
  end


  defp split_map_recurse(data, size, process_fun, acc) when byte_size(data) >= size do
    << part :: binary-size(size), rest :: binary >> = data
    item = Kernel.apply(process_fun, [part])
    split_map_recurse(rest, size, process_fun, [item|acc])
  end


  defp split_map_recurse(data, _size, _process_fun, acc) do
    {:ok, {acc |> Enum.reverse, data}}
  end
end
