defmodule Membrane.Element.Base.Source do

  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SourceBehaviour


      @doc """
      Returns module that manages this element.
      """
      @spec manager_module() :: module
      def manager_module, do: Membrane.Element.Manager.Source


      # Default implementations

      @doc false
      def handle_demand1(_pad, _params, state), do:
        {{:error, :handle_demand_not_implemented}, state}

      @doc false
      def handle_demand(pad, size, :buffers, params, state) do
        1..size |> Membrane.Element.Manager.Common.reduce_something1_results(state, fn _, st ->
            handle_demand1 pad, params, st
          end)
      end
      def handle_demand(_pad, _size, _unit, _params, state), do:
        {{:error, :handle_demand_not_implemented}, state}


      defoverridable [
        handle_demand1: 3,
        handle_demand: 5,
      ]
    end
  end
end
