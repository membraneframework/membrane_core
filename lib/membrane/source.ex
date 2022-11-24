defmodule Membrane.Source do
  @moduledoc """
  Module that should be used in sources - elements producing data. Declares
  appropriate behaviours implementation and provides default callbacks implementation.

  Behaviours for sources are specified in modules
  `Membrane.Element.Base` and
  `Membrane.Element.WithOutputPads`.

  Source elements can define only output pads. Job of a usual source is to produce
  some data (read from soundcard, download through HTTP, etc.) and send it through
  such pad. If the pad works in pull mode, then element is also responsible for
  receiving demands and send buffers only if they have previously been demanded
  (for more details, see `c:Membrane.Element.WithOutputPads.handle_demand/5`
  callback).
  Sources, like all elements, can of course have multiple pads if needed to
  provide more complex solutions.
  """

  @doc """
  Brings all the stuff necessary to implement a source element.

  Options:
    - `:bring_pad?` - if true (default) requires and aliases `Membrane.Pad`
  """
  alias Membrane.Core.DocsHelper

  defmacro __using__(options) do
    quote location: :keep do
      use Membrane.Element.Base, unquote(options)
      use Membrane.Element.WithOutputPads

      @doc false
      @spec membrane_element_type() :: Membrane.Element.type_t()
      def membrane_element_type, do: :source
    end
  end

  DocsHelper.add_callbacks_list_to_moduledoc(
    __MODULE__,
    [Membrane.Element.Base, Membrane.Element.WithOutputPads]
  )
end
