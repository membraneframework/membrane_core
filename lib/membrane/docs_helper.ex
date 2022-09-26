defmodule Membrane.DocsHelper  do
  @moduledoc """
  A module with function to generate a docstring with list of callbacks available
  in a given component.
  """

  def generate_callbacks_description_from_modules_list(module, modules_list) do
    this_module_callbacks = Enum.map(Module.get_attribute(module, :callback), fn {:callback, {:"::", _line1, [{name, _line2, array} | _rest ]}, _subtree} -> {{name, length(array)}, module} end)
    inherited_callbacks = Enum.flat_map(modules_list, fn module -> Enum.map(module.behaviour_info(:callbacks), & {&1, module} )end)
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
end
