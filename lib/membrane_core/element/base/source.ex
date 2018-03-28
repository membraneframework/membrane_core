defmodule Membrane.Element.Base.Source do
  alias Membrane.Element.Base.Mixin

  @callback handle_demand1(
              Pad.name_t(),
              Context.Demand.t(),
              State.internal_state_t()
            ) :: CommonBehaviour.callback_return_t()

  defmacro __using__(_) do
    quote location: :keep do
      use Mixin.CommonBehaviour
      use Mixin.SourceBehaviour

      @behaviour unquote(__MODULE__)

      @impl true
      def manager_module, do: Membrane.Element.Manager.Source

      @impl true
      def handle_demand1(_pad, _context, state),
        do: {{:error, :handle_demand_not_implemented}, state}

      @impl true
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
