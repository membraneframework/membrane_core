defmodule Membrane.Helper.Enum do
  @moduledoc """
  Module containing helper functions for manipulating enums.
  """

  import Enum
  use Membrane.Helper

  def chunk_by(enum, chunker, collector) do
    enum
      |> Enum.to_list
      ~> (
        [h|t] -> chunk_by t, chunker, collector, [[h]]
        [] -> []
        )
  end

  defp chunk_by([h | t], chunker, collector, [[lh | lt] | acc]) do
    chunk_by t, chunker, collector, (if chunker.(h, lh)
      do [[h, lh | lt] | acc]
      else [[h], [lh | lt] |> Enum.reverse |> collector.() | acc]
      end)
  end
  defp chunk_by([], _chunker, collector, [l | acc]) do
    [l |> Enum.reverse |> collector.() | acc] |> Enum.reverse
  end

  def reduce_with(enum, acc, f) do
    Enum.reduce_while enum, {:ok, acc}, fn e, {:ok, acc} ->
      with {:ok, new_acc} <- f.(e, acc)
      do {:cont, {:ok, new_acc}}
      else {:error, reason} -> {:halt, {:error, {reason, acc}}}
      end
    end
  end

  def each_with(enum, f), do: do_each_with(enum |> Enum.to_list, f)
  defp do_each_with([], _f), do: :ok
  defp do_each_with([h|t], f) do
    with :ok <- f.(h)
    do each_with t, f
    else {:error, reason} -> {:error, reason}
    end
  end


  def map_with(enum, f), do: map_with(enum |> Enum.to_list, f, [])
  defp map_with([], _f, acc), do: {:ok, acc |> Enum.reverse}
  defp map_with([h|t], f, acc) do
    with {:ok, res} <- f.(h)
    do map_with t, f, [res|acc]
    else {:error, reason} -> {:error, reason}
    end
  end

  def map_reduce_with(enum, acc, f), do: map_reduce_with(enum |> Enum.to_list, acc, f, [])
  defp map_reduce_with([], f_acc, _f, acc), do: ok(acc |> Enum.reverse, f_acc)
  defp map_reduce_with([h|t], f_acc, f, acc) do
    with {{:ok, res}, f_acc} <- f.(h, f_acc)
    do map_reduce_with t, f_acc, f, [res|acc]
    else
      error reason, f_acc -> error reason, f_acc
      error reason -> error reason, f_acc
    end
  end


  @doc """
  Works the same way as Enum.zip/1, but does not cut off remaining values.

  ## Examples:
    iex> x = [[1, 2] ,[3 ,4, 5]]
    iex> Enum.zip(x)
    [{1, 3}, {2, 4}]
    iex> zip_longest(x)
    [[1, 3], [2, 4], [5]]

  It also returns list of lists, as opposed to tuples.
  """
  @spec zip_longest([] | [...]) :: [] | [...]
  def zip_longest(lists) when is_list(lists) do
    zip_longest_recurse(lists, [])
  end

  defp zip_longest_recurse(lists, acc) do
    {lists, zipped} = lists
      |> reject(&empty?/1)
      |> map_reduce([], fn [h|t], acc -> {t, [h | acc]} end)

    if zipped |> empty? do
      reverse acc
    else
      zipped = zipped |> reverse
      zip_longest_recurse(lists, [zipped | acc])
    end
  end


  @doc """
  Implementation of Enum.unzip/1 for more-than-two-element tuples. Accepts
  arguments:

    - List to be unzipped,

    - Size of each tuple in this list.

  Returns {:ok, result} if there is no error.

  Returns {:error, reason} if encounters a tuple of size different from
  tuple_size argument.

  As such function is planned to be supplied in Enum module, it should replace
  this one once it happens.
  """
  @spec unzip([] | [...], pos_integer) :: {:ok, Tuple.t} | {:error, any}
  def unzip(list, tuple_size)
  when is_list(list) and is_integer(tuple_size) and tuple_size >= 2 do
    unzip_recurse(list |> reverse, tuple_size, 1..tuple_size |> into([], fn _ -> [] end))
  end

  @doc """
  Same as above, returns plain result, throws match error if something goes wrong.
  """
  @spec unzip!([] | [...], pos_integer) :: Tuple.t
  def unzip!(list, tuple_size)
  when is_list(list) and is_integer(tuple_size) and tuple_size >= 2 do
    {:ok, result} = unzip(list, tuple_size)
    result
  end

  defp unzip_recurse([], _tuple_size, acc) do
    {:ok, acc |> List.to_tuple}
  end
  defp unzip_recurse([h|t], tuple_size, acc) when is_tuple(h) do
    l = h |> Tuple.to_list
    if tuple_size != l |> length do
      {:error, "tuple #{inspect h} is not #{inspect tuple_size}-element long"}
    else
      unzip_recurse t, tuple_size, zip(l, acc) |> map(fn {t, r} -> [t | r] end)
    end
  end

end
