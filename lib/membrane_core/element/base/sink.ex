defmodule Membrane.Element.Base.Sink do

  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SinkBehaviour


      @doc """
      Returns module that manages this element.
      """
      @spec manager_module() :: module
      def manager_module, do: Membrane.Element.Manager.Sink


      # Default implementations

      @doc false
      def handle_write1(_pad, _buffer, _params, state), do: {:ok, state}

      @doc false
      def handle_write(pad, buffers, params, state) do
        buffers |> Membrane.Element.Manager.Common.reduce_something1_results(state, fn buf, st ->
            handle_write1 pad, buf, params, st
          end)
      end


      defoverridable [
        handle_write: 4,
        handle_write1: 4,
      ]
    end
  end
end
