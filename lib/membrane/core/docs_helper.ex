defmodule Membrane.Core.DocsHelper do
  @moduledoc false

  @doc """
  A function that appends a list of callbacks to the @moduledoc of a given argument.

  The list of callbacks is fetched out of the callbacks defined by that module, passed as the
  first argument, and the callbacks fetched from each of the modules passed as a list in second argument.
  The third argument filter the callbacks that should be put into the @moduledoc, as it is a prefix of the
  callback names that are desired to be put there.
  """
  @spec add_callbacks_list_to_moduledoc(module(), list(module())) :: :ok
  def add_callbacks_list_to_moduledoc(module, inherited_modules_list \\ []) do
    {line, docstring} = Module.get_attribute(module, :moduledoc)

    inherited_modules_callbacks =
      for module <- inherited_modules_list, do: get_callbacks_in_compiled_module(module)

    this_module_callbacks = get_callbacks_in_uncompiled_module(module)

    {callbacks_per_module_list, all_modules} =
      if this_module_callbacks == [],
        do: {inherited_modules_callbacks, inherited_modules_list},
        else:
          {[
             this_module_callbacks | inherited_modules_callbacks
           ], [module | inherited_modules_list]}

    new_docstring = """
    #{docstring}
    ## List of available callbacks
    Below there is a list of all the callbacks available in a module, that implements `#{inspect(module)}` behaviour.
    We have put it for your convenience, as some of these callbacks might not be directly defined in that module and
    their specification is available in different modules.

    The callbacks available in `#{inspect(module)}` behaviour:

    #{Enum.zip(all_modules, callbacks_per_module_list) |> Enum.map_join(fn {module, callbacks_list} -> """
      `#{inspect(module)}`
      #{generate_docstring_with_list_of_callbacks(callbacks_list)}
      """ end)}
    """

    Module.put_attribute(module, :moduledoc, {line, new_docstring})
  end

  defp generate_docstring_with_list_of_callbacks(list_of_callbacks) do
    callbacks_names =
      list_of_callbacks
      |> Enum.map(fn {{name, arity}, module} ->
        "`c:#{inspect(module)}.#{Atom.to_string(name)}/#{arity}`"
      end)

    """
    #{"* " <> Enum.join(callbacks_names, "\n* ")}
    """
  end

  defp get_callbacks_in_compiled_module(module) do
    Enum.map(module.behaviour_info(:callbacks), &{&1, module})
  end

  defp get_callbacks_in_uncompiled_module(module) do
    Enum.map(
      Module.get_attribute(module, :callback),
      fn
        {:callback,
         {:when, _line,
          [
            callback_ast,
            _rest
          ]}, _rest2} ->
          {parse_callback_ast(callback_ast), module}

        {:callback, callback_ast, _subtree} ->
          {parse_callback_ast(callback_ast), module}
      end
    )
  end

  defp parse_callback_ast({:"::", _line1, [{name, _line2, args} | _rest]}) do
    {name, if(is_nil(args), do: 0, else: length(args))}
  end
end
