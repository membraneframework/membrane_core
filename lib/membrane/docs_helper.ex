defmodule Membrane.DocsHelper do
  @moduledoc """
  A module with function to generate a docstring with list of callbacks available
  in a given component.
  """

  @spec generate_docstring_with_list_of_callbacks(module(), list(module())) :: String.t()
  def generate_docstring_with_list_of_callbacks(module, modules_list) do
    this_module_callbacks = get_callbacks_in_module(module)

    inherited_callbacks =
      Enum.flat_map(modules_list, fn module ->
        Enum.map(module.behaviour_info(:callbacks), &{&1, module})
      end)

    callbacks_names =
      (inherited_callbacks ++ this_module_callbacks)
      |> Enum.filter(fn {{name, _arity}, _module} ->
        String.starts_with?(Atom.to_string(name), "handle_")
      end)
      |> Enum.map(fn {{name, arity}, module} ->
        "`c:#{inspect(module)}.#{Atom.to_string(name)}/#{arity}`"
      end)

    """
    #{"* " <> Enum.join(callbacks_names, "\n* ")}
    """
  end

  defp get_callbacks_in_module(module) do
    Enum.map(
      Module.get_attribute(module, :callback),
      fn
        {:callback, {:"::", _line1, [{name, _line2, array} | _rest]}, _subtree} ->
          {{name, if(is_nil(array), do: 0, else: length(array))}, module}

        {:callback,
         {:when, _line1,
          [
            {:"::", _line2,
             [
               {name, _line3, array},
               :ok
             ]},
            _rest
          ]}, _rest2} ->
          {{name, if(is_nil(array), do: 0, else: length(array))}, module}
      end
    )
  end
end
