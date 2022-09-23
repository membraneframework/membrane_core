defmodule Membrane.CallbacksSummary.DocsHelper  do
  def generate_callbacks_description(module) do
    Module.create(ReflectionModule, quote do
      use unquote(module)
    end, Macro.Env.location(__ENV__))
    modules_list = ReflectionModule.module_info(:attributes) |> Enum.filter(fn {attr_name, _value} -> attr_name == :behaviour end) |> Enum.map(fn {_attr_name, value} -> value end)
    |> Enum.reduce(& &1++&2)
    callbacks = Enum.flat_map(modules_list, fn module -> Enum.map(module.behaviour_info(:callbacks), & {&1, module} )end)
    callbacks_names =
    callbacks
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

defmodule Membrane.CallbacksSummary do
  import Membrane.CallbacksSummary.DocsHelper
  @moduledoc """
  A list of callbacks available in each component type.
  ## Filter
  #{generate_callbacks_description(Membrane.Filter)}

  ## Source
  #{generate_callbacks_description(Membrane.Source)}

  ## Sink
  #{generate_callbacks_description(Membrane.Sink)}

  ## Pipeline
  #{generate_callbacks_description(Membrane.Pipeline)}

  ## Bin
  #{generate_callbacks_description(Membrane.Bin)}
  """
end
