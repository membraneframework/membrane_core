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
      def handle_demand1(_pad, _context, state),
        do: {{:error, :handle_demand_not_implemented}, state}

      @doc false
      def handle_demand(pad, size, :buffers, context, state) do
        args_list =
          Stream.repeatedly(fn -> nil end)
          |> Stream.take(size)
          |> Enum.map(fn _ -> [pad, context] end)

        {{:ok, split: {:handle_demand1, args_list}}, state}
      end

      def handle_demand(_pad, _size, _unit, _context, state),
        do: {{:error, :handle_demand_not_implemented}, state}

      defoverridable handle_demand1: 3,
                     handle_demand: 5
    end
  end
end
