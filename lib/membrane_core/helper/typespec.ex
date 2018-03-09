defmodule Membrane.Helper.Typespec do

  defmacro def_type_from_list(type) do

    {:::, _, [{name, _, _}, list]} = type
    list = quote do unquote(list) |> Enum.reduce(fn a, b -> {:|, [], [a, b]} end) end
    type = {:{}, [], [:::, [], [{:{}, [], [name, [], Elixir]}, list]]}

    pos = :elixir_locals.cache_env(__CALLER__)
    %{line: line, file: file, module: module} = __CALLER__

    quote do
      Kernel.Typespec.deftype(
        :type,
        unquote(type),
        unquote(line),
        unquote(file),
        unquote(module),
        unquote(pos)
      )
    end
  end

end
