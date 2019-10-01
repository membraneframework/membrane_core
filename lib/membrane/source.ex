defmodule Membrane.Source do
  @moduledoc """
  Module that should be used in sources - elements producing data. Declares
  appropriate behaviours implementation and provides default callbacks implementation.

  Behaviours for sources are specified in modules
  `Membrane.Element.Base` and
  `Membrane.WithOutputPads`.

  Source elements can define only output pads. Job of a usual source is to produce
  some data (read from soundcard, download through HTTP, etc.) and send it through
  such pad. If the pad works in pull mode, then element is also responsible for
  receiving demands and send buffers only if they have previously been demanded
  (for more details, see `c:Membrane.WithOutputPads.handle_demand/5`
  callback).
  Sources, like all elements, can of course have multiple pads if needed to
  provide more complex solutions.
  """

  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base
      use Membrane.WithOutputPads

      @impl true
      def membrane_element_type, do: :source
    end
  end
end
