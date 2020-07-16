defmodule Membrane.Core.Child do
  @moduledoc false
  alias Membrane.{Bin, Core, Element}

  defmacro callback_context_generator(module, state, args \\ []) do
    quote do
      require unquote(element_context(module))
      require unquote(bin_context(module))

      case unquote(state) do
        %Core.Element.State{} -> &unquote(element_context(module)).from_state(&1, unquote(args))
        %Core.Bin.State{} -> &unquote(bin_context(module)).from_state(&1, unquote(args))
      end
    end
  end

  defp element_context(module),
    do: Module.concat(Element.CallbackContext, Macro.expand(module, __ENV__))

  defp bin_context(module),
    do: Module.concat(Bin.CallbackContext, Macro.expand(module, __ENV__))
end
