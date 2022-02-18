defmodule FastMap do
  defmacro get_in(map, keys) do
    value_var = Macro.unique_var(:value, __MODULE__)

    match =
      keys
      |> Enum.reverse()
      |> Enum.reduce(value_var, fn key, acc ->
        quote do
          %{unquote(key) => unquote(acc)}
        end
      end)

    quote do
      unquote(match) = unquote(map)
      unquote(value_var)
    end
  end

  defmacro update_in(map, keys, fun) do
    map_var = Macro.unique_var(:map, __MODULE__)
    {matches, vars} = gen_matches_and_vars(keys, map_var)

    old_value = List.last(vars)
    new_value = Macro.unique_var(:new_value, __MODULE__)
    {:fn, _meta1, [{:->, _meta2, [[fun_arg], fun_body]}]} = fun

    update =
      quote do
        unquote(fun_arg) = unquote(old_value)
        unquote(new_value) = unquote(fun_body)
      end

    insert = gen_insert(keys, map_var, vars, new_value)

    result =
      quote do
        unquote(map_var) = unquote(map)
        unquote_splicing(matches)
        unquote(update)
        unquote(insert)
      end

    # result |> Macro.to_string() |> IO.puts()
    result
  end

  defmacro set_in(map, keys, value) do
    map_var = Macro.unique_var(:map, __MODULE__)
    {matches, vars} = gen_matches_and_vars(List.delete_at(keys, -1), map_var)
    insert = gen_insert(keys, map_var, vars, value)

    result =
      quote do
        unquote(map_var) = unquote(map)
        unquote_splicing(matches)
        unquote(insert)
      end

    # result |> Macro.to_string() |> IO.puts()
    result
  end

  defp gen_matches_and_vars(keys, map_var) do
    {matches_and_vars, _i} =
      Enum.map_reduce(keys, {map_var, 0}, fn key, {map, i} ->
        var = Macro.unique_var(:"nested_var#{i}", __MODULE__)

        match =
          quote do
            %{unquote(key) => unquote(var)} = unquote(map)
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
