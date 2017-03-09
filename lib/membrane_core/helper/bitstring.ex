defmodule Membrane.Helper.Bitstring do
  @moduledoc """
  Module containing helper functions for manipulating bitstrings.
  """

  @doc """
    Splits given bitstring into parts of given size. Returns {:ok, list of
    bitstrings, remaining bitstrings}
  """
  @spec split(bitstring, pos_integer) :: {:ok, [] | [...], bitstring}
  def split(data, chunk_size)
  when is_bitstring(data) and is_integer(chunk_size) and chunk_size > 0 do
    split_recurse(data, chunk_size, [])
  end

  @doc """
    Same as above, but returns only list of chunks, remaining part is not
    cut off
  """
  @spec split!(bitstring, pos_integer) :: [] | [...]
  def split!(data, chunk_size)
  when is_bitstring(data) and is_integer(chunk_size) and chunk_size > 0 do
    {:ok, result, _} = split(data, chunk_size)
    result
  end

  defp split_recurse(data, chunk_size, acc) do
    case data do
      <<chunk::binary-size(chunk_size)>> <> rest ->
        split_recurse rest, chunk_size, [chunk | acc]
      rest -> {:ok, acc |> Enum.reverse, rest}
    end
  end


  @doc """
  Splits given bitstring into parts of given size, and calls given function
  for each part.

  Passed processing function has to accept at least one argument that will
  be always a bitstring representing current part.

  Additionally you may pass a list of extra arguments that will be passed
  as second and further arguments to the given function.

  Processing function should return `{:ok, value}` on success and
  `{:error, reason}` otherwise. Returning `{:error, reason}` will break the
  recursion.

  It accumulates return values of all successful function calls.

  In case of success, returns `{:ok, {accumulated_result, remaining_bitstring}}`.
  In case of failure, returns `{:error, reason}`.

  This function is useful for handling buffer's payload if element's logic
  expects to process certain amount of samples in one pass. For example,
  Opus encoder expects to receive particular amount of samples, which total
  duration is equal to the selected frame size duration, but there's no guarantee
  that incoming buffer contains exactly requested amount of samples.
  """
  @spec split_map(bitstring, pos_integer, fun, [] | [...]) ::
    {:ok, {[] | [...], bitstring}} |
    {:error, any}
  def split_map(data, size, process_fun, extra_fun_args \\ [])
  when is_bitstring(data) and is_integer(size) and size > 0 and
       is_function(process_fun) and is_list(extra_fun_args) do
    split_map_recurse(data, size, process_fun, extra_fun_args, [])
  end


  defp split_map_recurse(data, size, process_fun, extra_fun_args, acc)
  when byte_size(data) >= size do
    << part :: binary-size(size), rest :: binary >> = data
    case Kernel.apply(process_fun, [part] ++ extra_fun_args) do
      {:ok, item} ->
        split_map_recurse(rest, size, process_fun, extra_fun_args, [item|acc])
      {:error, reason} ->
        {:error, reason}
    end
  end


  defp split_map_recurse(data, _size, _process_fun, _extra_fun_args, acc) do
    {:ok, {acc |> Enum.reverse, data}}
  end


  @doc """
  Works similarily to `split_map/4` but does not accumulate return values.

  Processing function should return `:ok` on success and `{:error, reason}`
  otherwise. Returning `{:error, reason}` will break the recursion.

  In case of success, returns `{:ok, remaining_bitstring}`.
  In case of failure, returns `{:error, reason}`.
  """
  @spec split_each(bitstring, pos_integer, fun, [] | [...]) ::
    {:ok, bitstring} |
    {:error, any}
  def split_each(data, size, process_fun, extra_fun_args \\ [])
  when is_bitstring(data) and is_integer(size) and size > 0 and
       is_function(process_fun) and is_list(extra_fun_args)do
    split_each_recurse(data, size, process_fun, extra_fun_args)
  end


  defp split_each_recurse(data, size, process_fun, extra_fun_args)
  when byte_size(data) >= size do
    << part :: binary-size(size), rest :: binary >> = data
    case Kernel.apply(process_fun, [part] ++ extra_fun_args) do
      :ok ->
        split_each_recurse(rest, size, process_fun, extra_fun_args)
      {:error, reason} ->
        {:error, reason}
    end
  end


  defp split_each_recurse(data, _size, _process_fun, _extra_fun_args) do
    {:ok, data}
  end
end
