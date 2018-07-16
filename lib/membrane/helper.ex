defmodule Membrane.Helper do
  @moduledoc """
  Module containing various helper functions that improve code readability
  """

  defmacro __using__(_args) do
    quote do
      import unquote(__MODULE__),
        only: [withl: 1, withl: 2, ~>: 2, ~>>: 2, provided: 2, int_part: 2]

      alias unquote(__MODULE__)
    end
  end

  @compile {:inline, listify: 1, wrap_nil: 2, int_part: 2}

  @doc """
  A labeled version of the `with` macro.

  Helps to determine in `else` block which `with clause` did not match.
  Therefore `else` block is always required. Due to the Elixir syntax requirements,
  all clauses have to be labeled.

  Labels also make it possible to access results of already succeeded matches
  from else clauses. That is why labels have to be known at the compile time.

  Sample usage:
  ```
  iex> use Membrane.Helper
  iex> list = [-1, 3, 2]
  iex> binary = <<1,2>>
  iex> withl max: i when i > 0 <- list |> Enum.max(),
  ...>       bin: <<b::binary-size(i), _::binary>> <- binary do
  ...>   {list, b}
  ...> else
  ...>   max: i -> {:error, :invalid_maximum, i}
  ...>   bin: b -> {:error, :binary_too_short, b, i}
  ...> end
  {:error, :binary_too_short, <<1,2>>, 3}
  ```
  """
  @spec withl(keyword(with_clause :: term), do: code_block :: term(), else: match_clauses :: term) ::
          term
  defmacro withl(with_clauses, do: block, else: else_clauses) do
    do_withl(with_clauses, block, else_clauses)
  end

  @doc """
  Works like `withl/2`, but allows shorter syntax.

  Sample usage:
  ```
  iex> use Membrane.Helper
  iex> x = 1
  iex> y = 2
  iex> withl a: true <- x > 0,
  ...>       b: false <- y |> rem(2) == 0,
  ...>       do: {x, y},
  ...>       else: (a: false -> {:error, :x}; b: true -> {:error, :y})
  {:error, :y}
  ```

  For more details and more verbose and readable syntax, check docs for `withl/2`.
  """
  @spec withl(
          keyword :: [
            {key :: atom(), with_clause :: term}
            | {:do, code_block :: term}
            | {:else, match_clauses :: term}
          ]
        ) :: term
  defmacro withl(keyword) do
    {{:else, else_clauses}, keyword} = keyword |> List.pop_at(-1)
    {{:do, block}, keyword} = keyword |> List.pop_at(-1)
    with_clauses = keyword
    do_withl(with_clauses, block, else_clauses)
  end

  defp do_withl(with_clauses, block, else_clauses) do
    else_clauses =
      else_clauses
      |> Enum.map(fn {:->, meta, [[[{label, left}]], right]} ->
        {label, {:->, meta, [[left], right]}}
      end)
      |> Enum.group_by(fn {k, _v} -> k end, fn {_k, v} -> v end)

    with_clauses
    |> Enum.reverse()
    |> Enum.reduce(block, fn {label, clause}, acc ->
      else_block =
        case else_clauses[label] do
          nil -> []
          clauses -> [else: clauses]
        end

      args = [clause, [do: acc] ++ else_block]

      quote do
        with unquote_splicing(args)
      end
    end)
  end

  def listify(list) when is_list(list) do
    list
  end

  def listify(non_list) do
    [non_list]
  end

  def wrap_nil(nil, reason), do: {:error, reason}
  def wrap_nil(v, _), do: {:ok, v}

  def result_with_status({:ok, _state} = res), do: {:ok, res}
  def result_with_status({{:ok, _res}, _state} = res), do: {:ok, res}
  def result_with_status({{:error, reason}, _state} = res), do: {{:error, reason}, res}
  def result_with_status({:error, reason} = res), do: {{:error, reason}, res}

  def int_part(x, d) when is_integer(x) and is_integer(d) do
    r = x |> rem(d)
    x - r
  end

  defmacro x ~> match_clauses when is_list(match_clauses) do
    quote do
      case unquote(x) do
        unquote(match_clauses)
      end
    end
  end

  defmacro x ~> lambda do
    quote do
      unquote({:&, [], [lambda]}).(unquote(x))
    end
  end

  defmacro x ~>> match_clauses do
    default =
      quote do
        _ -> unquote(x)
      end

    quote do
      case unquote(x) do
        unquote(match_clauses ++ default)
      end
    end
  end

  defmacro provided(value, that: condition, else: default) do
    quote do
      if unquote(condition) do
        unquote(value)
      else
        unquote(default)
      end
    end
  end

  defmacro provided(value, that: condition) do
    quote do
      if unquote(condition) do
        unquote(value)
      else
        []
      end
    end
  end

  defmacro provided(value, do: condition, else: default) do
    quote do
      if unquote(condition) do
        unquote(value)
      else
        unquote(default)
      end
    end
  end

  defmacro provided(value, do: condition) do
    quote do
      if unquote(condition) do
        unquote(value)
      else
        []
      end
    end
  end

  defmacro provided(value, not: condition, else: default) do
    quote do
      if !unquote(condition) do
        unquote(value)
      else
        unquote(default)
      end
    end
  end

  defmacro provided(value, not: condition) do
    quote do
      if !unquote(condition) do
        unquote(value)
      else
        []
      end
    end
  end

  defmacro stacktrace do
    quote do
      # drop excludes `Process.info/2` call
      Process.info(self(), :current_stacktrace)
      ~> ({:current_stacktrace, trace} -> trace)
      |> Enum.drop(1)
      |> Exception.format_stacktrace()
    end
  end
end
