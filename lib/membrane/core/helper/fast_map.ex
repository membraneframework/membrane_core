defmodule Membrane.Core.Helper.FastMap do
  @moduledoc false

  defmacro get_in(map, keys) do
    get_in_code(map, keys)
  end

  @spec get_in_code(map :: Macro.t(), keys :: [Macro.t()]) :: Macro.t()
  def get_in_code(map, keys) do
    map_var = Macro.unique_var(:map, Elixir)
    value_var = Macro.unique_var(:value, Elixir)
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

  defmacro update_in(map, keys, fun) do
    update_in_code(map, keys, fun)
  end

  @spec update_in_code(map :: Macro.t(), keys :: [Macro.t()], fun :: Macro.t()) :: Macro.t()
  def update_in_code(map, keys, fun) do
    map_var = Macro.unique_var(:map, Elixir)
    {key_vars, key_assignments} = gen_key_vars_and_assignments(keys)
    {matches, vars} = gen_matches_and_vars(key_vars, map_var)

    old_value = List.last(vars)
    new_value = Macro.unique_var(:new_value, Elixir)

    update =
      quote do
        unquote(new_value) = unquote(fun).(unquote(old_value))
      end

    insert = gen_insert(key_vars, map_var, vars, new_value)

    quote do
      unquote(map_var) = unquote(map)
      unquote_splicing(key_assignments)
      unquote_splicing(matches)
      unquote(update)
      unquote(insert)
    end
  end

  defmacro get_and_update_in(map, keys, fun) do
    get_and_update_in_code(map, keys, fun)
  end

  @spec get_and_update_in_code(map :: Macro.t(), keys :: [Macro.t()], fun :: Macro.t()) ::
          Macro.t()
  def get_and_update_in_code(map, keys, fun) do
    map_var = Macro.unique_var(:map, Elixir)
    {key_vars, key_assignments} = gen_key_vars_and_assignments(keys)
    {matches, vars} = gen_matches_and_vars(key_vars, map_var)

    old_value = List.last(vars)
    new_value = Macro.unique_var(:new_value, Elixir)
    get_value = Macro.unique_var(:get_value, Elixir)

    update =
      quote do
        {unquote(get_value), unquote(new_value)} = unquote(fun).(unquote(old_value))
      end

    insert = gen_insert(key_vars, map_var, vars, new_value)

    quote do
      unquote(map_var) = unquote(map)
      unquote_splicing(key_assignments)
      unquote_splicing(matches)
      unquote(update)
      {unquote(get_value), unquote(insert)}
    end
  end

  defmacro set_in(map, keys, value) do
    set_in_code(map, keys, value)
  end

  @spec set_in_code(map :: Macro.t(), keys :: [Macro.t()], value :: Macro.t()) :: Macro.t()
  def set_in_code(map, keys, value) do
    map_var = Macro.unique_var(:map, Elixir)
    {key_vars, key_assignments} = gen_key_vars_and_assignments(keys)
    {matches, vars} = gen_matches_and_vars(List.delete_at(key_vars, -1), map_var)
    insert = gen_insert(key_vars, map_var, vars, value)

    quote do
      unquote(map_var) = unquote(map)
      unquote_splicing(key_assignments)
      unquote_splicing(matches)
      unquote(insert)
    end
  end

  defp gen_key_vars_and_assignments(keys) do
    key_vars = Enum.map(0..(length(keys) - 1)//1, &Macro.unique_var(:"key_var#{&1}", Elixir))

    key_assignments =
      Enum.zip(keys, key_vars)
      |> Enum.map(fn {key, key_var} ->
        quote do
          unquote(key_var) = unquote(key)
        end
      end)

    {key_vars, key_assignments}
  end

  defp gen_matches_and_vars(keys, map_var) do
    {matches_and_vars, _i} =
      Enum.map_reduce(keys, {map_var, 0}, fn key, {map, i} ->
        var = Macro.unique_var(:"nested_var#{i}", Elixir)

        match =
          quote do
            %{^unquote(key) => unquote(var)} = unquote(map)
          end

        {{match, var}, {var, i + 1}}
      end)

    Enum.unzip(matches_and_vars)
  end

  defp gen_insert(keys, map_var, vars, value) do
    keys
    |> Enum.zip([map_var | vars])
    |> Enum.reverse()
    |> Enum.reduce(value, fn {key, submap}, acc ->
      quote do
        %{unquote(submap) | unquote(key) => unquote(acc)}
      end
    end)
  end
end
