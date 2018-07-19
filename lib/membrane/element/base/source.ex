defmodule Membrane.Element.Base.Source do
  @moduledoc """
  Module defining behaviour for sources - elements producing data.

  Behaviours for filters are specified, besides this place, in modules
  `Membrane.Element.Base.Mixin.CommonBehaviour`,
  `Membrane.Element.Base.Mixin.SourceBehaviour`.

  Source elements can define only source pads. Job of a usual source is to produce
  some data (read from soundcard, download through HTTP, etc.) and send it through
  such pad. If the pad works in pull mode, then element is also responsible for
  receiving demands, and send buffers only if they have previously been demanded
  (for more details, see `c:Membrane.Element.Base.Mixin.SourceBehaviour.handle_demand/5`
  callback).
  Sources, like all elements, can of course have multiple pads if needed to
  provide more complex solutions.
  """

  alias Membrane.Element
  alias Element.Base.Mixin
  alias Element.{CallbackContext, Pad}

  @doc """
  Callback that is called when buffers should be emitted by the source.
  In contrast to `c:Membrane.Element.Base.Mixin.SourceBehaviour.handle_demand/5`,
  size is not passed, but should always be considered to equal 1.

  Called by default implementation of
  `c:Membrane.Element.Base.Mixin.SourceBehaviour.handle_demand/5`, check documentation
  for that callback for more information.
  """
  @callback handle_demand1(
              pad :: Pad.name_t(),
              context :: CallbackContext.Demand.t(),
              state :: Element.state_t()
            ) :: Mixin.CommonBehaviour.callback_return_t()

  defmacro __using__(_) do
    quote location: :keep do
      use Mixin.CommonBehaviour
      use Mixin.SourceBehaviour

      @behaviour unquote(__MODULE__)

      @impl true
      def membrane_element_type, do: :source

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
