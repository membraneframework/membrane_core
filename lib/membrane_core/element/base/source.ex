defmodule Membrane.Element.Manager.Base.Source do

  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SourceBehaviour


      @doc """
      Returns module on which this Element is based.
      """
      @spec base_module() :: module
      def base_module, do: Membrane.Element.Manager.Source


      # Default implementations

      @doc false
      def handle_new_pad(_pad, _params, state), do: {:error, :adding_pad_unsupported}

      @doc false
      def handle_pad_added(_pad, state), do: {:ok, state}

      @doc false
      def handle_pad_removed(_pad, state), do: {:ok, state}

      @doc false
      def handle_demand1(_pad, _params, state), do:
        {{:error, :handle_demand_not_implemented}, state}

      @doc false
      def handle_demand(pad, size, :buffers, params, state) do
        1..size |> Common.reduce_something1_results(state, fn _, st ->
            handle_demand1 pad, params, st
          end)
      end
      def handle_demand(_pad, _size, _unit, _params, state), do:
        {{:error, :handle_demand_not_implemented}, state}

      @doc false
      def handle_event(_pad, _event, _params, state), do: {:ok, state}


      defoverridable [
        handle_new_pad: 3,
        handle_pad_added: 2,
        handle_pad_removed: 2,
        handle_demand1: 3,
        handle_demand: 5,
        handle_event: 4,
      ]
    end
  end
end
