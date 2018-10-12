defmodule Membrane.Element.Base.Source do
  @moduledoc """
  Module that should be used in sources - elements producing data. Declares
  appropriate behaviours implementation and provides default callbacks implementation.

  Behaviours for sources are specified in modules
  `Membrane.Element.Base.Mixin.CommonBehaviour` and
  `Membrane.Element.Base.Mixin.SourceBehaviour`.

  Source elements can define only output pads. Job of a usual source is to produce
  some data (read from soundcard, download through HTTP, etc.) and send it through
  such pad. If the pad works in pull mode, then element is also responsible for
  receiving demands and send buffers only if they have previously been demanded
  (for more details, see `c:Membrane.Element.Base.Mixin.SourceBehaviour.handle_demand/5`
  callback).
  Sources, like all elements, can of course have multiple pads if needed to
  provide more complex solutions.
  """

  alias Membrane.Element
  alias Element.Base.Mixin

  defmacro __using__(_) do
    quote location: :keep do
      use Mixin.CommonBehaviour
      use Mixin.SourceBehaviour

      @impl true
      def membrane_element_type, do: :source

      @impl true
      def handle_demand(_pad, _size, _unit, _context, state),
        do: {{:error, :handle_demand_not_implemented}, state}

      defoverridable handle_demand: 5
    end
  end
end
