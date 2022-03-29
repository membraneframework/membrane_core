defmodule Membrane.Core.Helper.FastMap do
  @moduledoc false

  @doc """
  Gets a value from a nested map structure

      iex> require #{inspect(__MODULE__)}
      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> #{inspect(__MODULE__)}.get_in!(users, ["john", :age])
      27

  Raises `MatchError` if there's no map under any of the nested keys.
  """
  defmacro get_in!(map, keys) do
    generate_get_in!(map, keys)
  end

  @doc """
  Generates AST for `get_in!/2`.
  """
  @spec generate_get_in!(map :: Macro.t(), keys :: [Macro.t()]) :: Macro.t()
  def generate_get_in!(map, keys) do
    map_var = unique_var(:map)
    value_var = unique_var(:value)
    {key_vars, key_assignments} = gen_key_vars_and_assignments(keys)

    match =
      key_vars
      |> Enum.reverse()
      |> Enum.reduce(value_var, fn key_var, acc ->
        quote do
          %{^unquote(key_var) => unquote(acc)}
        end
      end)

    quote do
      unquote(map_var) = unquote(map)
      unquote_splicing(key_assignments)
      unquote(match) = unquote(map_var)
      unquote(value_var)
    end
  end

  @doc """
  Updates a key in a nested map structure.

      iex> require #{inspect(__MODULE__)}
      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> #{inspect(__MODULE__)}.update_in!(users, ["john", :age], &(&1 + 1))
      %{"john" => %{age: 28}, "meg" => %{age: 23}}

  Raises `MatchError` if there's no map under any of the nested keys.
  """
  defmacro update_in!(map, keys, fun) do
    generate_update_in!(map, keys, fun)
  end

  @doc """
  Generates AST for `update_in!/3`.
  """
  @spec generate_update_in!(map :: Macro.t(), keys :: [Macro.t()], fun :: Macro.t()) :: Macro.t()
  def generate_update_in!(map, keys, fun) do
    map_var = unique_var(:map)
    {key_vars, key_assignments} = gen_key_vars_and_assignments(keys)
    {matches, vars} = gen_nested_matches_and_vars(key_vars, map_var)

    old_value = List.last(vars)
    new_value = unique_var(:new_value)

    update =
      quote do
        unquote(new_value) = unquote(fun).(unquote(old_value))
      end

    insert = gen_nested_insert(key_vars, map_var, vars, new_value)

    quote do
      unquote(map_var) = unquote(map)
      unquote_splicing(key_assignments)
      unquote_splicing(matches)
      unquote(update)
      unquote(insert)
    end
  end

  @doc """
  Gets a value and updates a nested map structure.

      iex> require #{inspect(__MODULE__)}
      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> #{inspect(__MODULE__)}.get_and_update_in!(users, ["john", :age], &{&1, &1 + 1})
      {27, %{"john" => %{age: 28}, "meg" => %{age: 23}}}

  Raises `MatchError` if there's no map under any of the nested keys.
  """
  defmacro get_and_update_in!(map, keys, fun) do
    generate_get_and_update_in!(map, keys, fun)
  end

  @doc """
  Generates AST for `get_and_update_in!/3`.
  """
  @spec generate_get_and_update_in!(map :: Macro.t(), keys :: [Macro.t()], fun :: Macro.t()) ::
          Macro.t()
  def generate_get_and_update_in!(map, keys, fun) do
    map_var = unique_var(:map)
    {key_vars, key_assignments} = gen_key_vars_and_assignments(keys)
    {matches, vars} = gen_nested_matches_and_vars(key_vars, map_var)

    old_value = List.last(vars)
    new_value = unique_var(:new_value)
    get_value = unique_var(:get_value)

    update =
      quote do
        {unquote(get_value), unquote(new_value)} = unquote(fun).(unquote(old_value))
      end

    insert = gen_nested_insert(key_vars, map_var, vars, new_value)

    quote do
      unquote(map_var) = unquote(map)
      unquote_splicing(key_assignments)
      unquote_splicing(matches)
      unquote(update)
      {unquote(get_value), unquote(insert)}
    end
  end

  @doc """
  Sets a value in a nested map structure.

      iex> require #{inspect(__MODULE__)}
      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> #{inspect(__MODULE__)}.set_in!(users, ["john", :age], 28)
      %{"john" => %{age: 28}, "meg" => %{age: 23}}

  All keys, including the last one must already be present in the structure.
  If the last key is not present, `KeyError` is raised. Raises `MatchError`
  if there's no map under any other nested key.
  """
  defmacro set_in!(map, keys, value) do
    generate_set_in!(map, keys, value)
  end

  @doc """
  Generates AST for `set_in!/3`.
  """
  @spec generate_set_in!(map :: Macro.t(), keys :: [Macro.t()], value :: Macro.t()) :: Macro.t()
  def generate_set_in!(map, keys, value) do
    map_var = unique_var(:map)
    {key_vars, key_assignments} = gen_key_vars_and_assignments(keys)
    {matches, vars} = gen_nested_matches_and_vars(List.delete_at(key_vars, -1), map_var)
    insert = gen_nested_insert(key_vars, map_var, vars, value)

    quote do
      unquote(map_var) = unquote(map)
      unquote_splicing(key_assignments)
      unquote_splicing(matches)
      unquote(insert)
    end
  end

  # Takes each chunk of code from a list, generates a variable for it
  # and code assigning it to the variable. Returns the list of variables
  # and the list of assignments.
  defp gen_key_vars_and_assignments(keys) do
    keys
    |> Enum.with_index()
    |> Enum.map(fn {key, index} ->
      key_var = unique_var(:"key_var#{index}")

      assignment =
        quote do
          unquote(key_var) = unquote(key)
        end

      {key_var, assignment}
    end)
    |> Enum.unzip()
  end

  # Generates `%{^key => value} = map` match for given `map_var`
  # and the first key. Then generates such matches for subsequent
  # keys, using previously matched `value` as a subsequent map.
  defp gen_nested_matches_and_vars(keys, map_var) do
    {matches_and_vars, _acc} =
      keys
      |> Enum.with_index()
      |> Enum.map_reduce(map_var, fn {key, i}, map ->
        var = unique_var(:"nested_var#{i}")

        match =
          quote do
            %{^unquote(key) => unquote(var)} = unquote(map)
          end

        {{match, var}, var}
      end)

    Enum.unzip(matches_and_vars)
  end

  # Generates a nested map insert in the following manner:
  # `%{map_var | key_0 => %{var_0 | key_1 => %{... => %{key_n => value}}}`
  defp gen_nested_insert(keys, map_var, vars, value) do
    keys
    |> Enum.zip([map_var | vars])
    |> Enum.reverse()
    |> Enum.reduce(value, fn {key, submap}, acc ->
      quote do
        %{unquote(submap) | unquote(key) => unquote(acc)}
      end
    end)
  end

  defp unique_var(name) do
    Macro.unique_var(name, __MODULE__)
  end
end
