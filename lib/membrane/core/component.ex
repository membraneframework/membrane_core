defmodule Membrane.Core.Component do
  @moduledoc false

  defmacro callback_context_generator(restrict, module, state, args \\ []) do
    module = Macro.expand(module, __ENV__)

    restrict =
      case restrict do
        :parent -> [Pipeline, Bin]
        :child -> [Bin, Element]
        :any -> [Pipeline, Bin, Element]
        restrict -> restrict
      end

    requires =
      restrict
      |> Enum.map(fn component ->
        quote do
          require unquote(context(component, module))
        end
      end)

    clauses =
      restrict
      |> Enum.flat_map(fn component ->
        quote do
          %unquote(state(component)){} ->
            &unquote(context(component, module)).from_state(&1, unquote(args))
        end
      end)

    quote do
      unquote_splicing(requires)
      unquote({:case, [], [state, [do: clauses]]})
    end
  end

  defp context(component, module),
    do: Module.concat([Membrane, component, CallbackContext, module])

  defp state(component), do: Module.concat([Membrane.Core, component, State])
end
