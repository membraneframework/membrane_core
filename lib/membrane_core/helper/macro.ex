defmodule Membrane.Helper.Macro do
  def inject_calls(ast, functions)
    when is_list(functions)
  do
    ast |> Macro.prewalk(fn ast_node ->
      functions |> Enum.reduce(ast_node, &replace_call(&2, &1))
    end)
  end

  def inject_call(ast, {module, fun_name})
    when is_atom(module) and is_atom(fun_name)
  do
    ast |> Macro.prewalk(fn ast_node ->
      replace_call(ast_node, {module, fun_name})
    end)
  end

  defp replace_call(ast_node, {module, fun_name})
    when is_atom(module) and is_atom(fun_name)
  do
    case ast_node do
      {^fun_name, _, args} ->
        quote do apply(unquote(module), unquote(fun_name), unquote(args)) end
      other_node ->
        other_node
    end
  end
end
