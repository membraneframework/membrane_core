defmodule Membrane.Helper.Bitstring do
  @moduledoc """
  Module containing helper functions to manipulate bitstrings.
  """


  @doc """
  Splits given bitstring into parts of given size, and calls given function
  for each part.

  Passed processing function has to accept at least one argument that will
  be always a bitstring representing current part.

  Additionally you may pass a list of extra arguments that will be passed
  as second and further arguments to the given function.

  It accumulates return values of all of such function calls.

  Returns `{:ok, {accumulated_result, remaining_bitstring}}`.

  This function is useful for handling buffer's payload if element's logic
  expects to process certain amount of samples in one pass. For example,
  Opus encoder expects to receive particular amount of samples, which total
  duration is equal to the selected frame size duration, but there's no guarantee
  that incoming buffer contains exactly requested amount of samples.

  Please note that size is expressed in bytes, not samples.
  """
  @spec split_map(bitstring, pos_integer, fun, [] | [...]) :: {:ok, {[] | [...], bitstring}}
  def split_map(data, size, process_fun, extra_fun_args \\ []) do
    split_map_recurse(data, size, process_fun, extra_fun_args, [])
  end


  defp split_map_recurse(data, size, process_fun, extra_fun_args, acc) when byte_size(data) >= size do
    << part :: binary-size(size), rest :: binary >> = data
    item = Kernel.apply(process_fun, [part] ++ extra_fun_args)
    split_map_recurse(rest, size, process_fun, extra_fun_args, [item|acc])
  end


  defp split_map_recurse(data, _size, _process_fun, _extra_fun_args, acc) do
    {:ok, {acc |> Enum.reverse, data}}
  end
end
