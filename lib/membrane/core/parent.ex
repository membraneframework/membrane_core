defmodule Membrane.Core.Parent do
  @moduledoc false
  alias Membrane.{Bin, Core, Pipeline}

  defmacro callback_context_generator(module, state, args \\ []) do
    quote do
      require unquote(pipeline_context(module))
      require unquote(bin_context(module))

      case unquote(state) do
        %Core.Pipeline.State{} -> &unquote(pipeline_context(module)).from_state(&1, unquote(args))
        %Core.Bin.State{} -> &unquote(bin_context(module)).from_state(&1, unquote(args))
      end
    end
  end

  defp pipeline_context(module),
    do: Module.concat(Pipeline.CallbackContext, Macro.expand(module, __ENV__))

  defp bin_context(module),
    do: Module.concat(Bin.CallbackContext, Macro.expand(module, __ENV__))
end
