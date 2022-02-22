defmodule FastMap do
  defmacro get_in(map, keys) do
    get_in_code(map, keys)
  end

  def get_in_code(map, keys) do
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

    result =
      quote do
        unquote(map_var) = unquote(map)
        unquote_splicing(key_assignments)
        unquote(match) = unquote(map_var)
        unquote(value_var)
      end

    # result |> Macro.to_string() |> IO.puts()
    result
  end

  # def get_in_code(map, keys) do
  #   map_var = unique_var(:map)
  #   {key_vars, key_assignments} = gen_key_vars_and_assignments(keys)
  #   {matches, vars} = gen_matches_and_vars(key_vars, map_var)

  #   result = quote do
  #     unquote(map_var) = unquote(map)
  #     unquote_splicing(key_assignments)
  #     unquote_splicing(matches)
  #     unquote(List.last(vars))
  #   end

  #   result |> Macro.to_string() |> IO.puts()
  #   result
  # end

  defmacro update_in(map, keys, fun) do
    update_in_code(map, keys, fun)
  end

  def update_in_code(map, keys, fun) do
    map_var = unique_var(:map)
    {key_vars, key_assignments} = gen_key_vars_and_assignments(keys)
    {matches, vars} = gen_matches_and_vars(key_vars, map_var)

    old_value = List.last(vars)
    new_value = unique_var(:new_value)
    {fun_arg, fun_body} = resolve_lambda(fun)

    update =
      quote do
        unquote(fun_arg) = unquote(old_value)
        unquote(new_value) = unquote(fun_body)
      end

    insert = gen_insert(key_vars, map_var, vars, new_value)

    result =
      quote do
        unquote(map_var) = unquote(map)
        unquote_splicing(key_assignments)
        unquote_splicing(matches)
        unquote(update)
        unquote(insert)
      end

    # result |> Macro.to_string() |> IO.puts()
    result
  end

  defmacro get_and_update_in(map, keys, fun) do
    get_and_update_in_code(map, keys, fun)
  end

  def get_and_update_in_code(map, keys, fun) do
    map_var = unique_var(:map)
    {key_vars, key_assignments} = gen_key_vars_and_assignments(keys)
    {matches, vars} = gen_matches_and_vars(key_vars, map_var)

    old_value = List.last(vars)
    new_value = unique_var(:new_value)
    get_value = unique_var(:get_value)
    {fun_arg, fun_body} = resolve_lambda(fun)

    update =
      quote do
        unquote(fun_arg) = unquote(old_value)
        {unquote(get_value), unquote(new_value)} = unquote(fun_body)
      end

    insert = gen_insert(key_vars, map_var, vars, new_value)

    result =
      quote do
        unquote(map_var) = unquote(map)
        unquote_splicing(key_assignments)
        unquote_splicing(matches)
        unquote(update)
        {unquote(get_value), unquote(insert)}
      end

    # result |> Macro.to_string() |> IO.puts()
    result
  end

  defmacro set_in(map, keys, value) do
    set_in_code(map, keys, value)
  end

  def set_in_code(map, keys, value) do
    map_var = unique_var(:map)
    {key_vars, key_assignments} = gen_key_vars_and_assignments(keys)
    {matches, vars} = gen_matches_and_vars(List.delete_at(key_vars, -1), map_var)
    insert = gen_insert(key_vars, map_var, vars, value)

    result =
      quote do
        unquote(map_var) = unquote(map)
        unquote_splicing(key_assignments)
        unquote_splicing(matches)
        unquote(insert)
      end

    result |> Macro.to_string() |> IO.puts()
    result
  end

  defp gen_key_vars_and_assignments(keys) do
    key_vars = Enum.map(0..(length(keys) - 1)//1, &unique_var(:"key_var#{&1}"))

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
        var = unique_var(:"nested_var#{i}")

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

  defp resolve_lambda({:fn, _meta1, [{:->, _meta2, [[fun_arg], fun_body]}]}) do
    {fun_arg, fun_body}
  end

  defp resolve_lambda({:&, _meta, [fun_body]}) do
    fun_arg = unique_var(:fun_arg)

    fun_body =
      Macro.prewalk(fun_body, fn
        {:&, _meta, [1]} -> fun_arg
        other -> other
      end)

    {fun_arg, fun_body}
  end

  defp unique_var(name) do
    # Macro.unique_var(:"#{name}_#{Enum.random(1..10000)}", Elixir)
    Macro.unique_var(name, Elixir)
  end
end
