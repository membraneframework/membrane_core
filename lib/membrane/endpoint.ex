defmodule Membrane.Endpoint do
  @moduledoc """
  Module defining behaviour for endpoints - elements consuming and producing data.

  Behaviours for endpoints are specified, besides this place, in modules
  `Membrane.Element.Base`,
  `Membrane.Element.WithOutputPads`,
  and `Membrane.Element.WithInputPads`.

  Endpoint can have both input and output pads. Job of usual endpoint is both, to
  receive some data on such pad and consume it (write to a soundcard, send through
  TCP etc.) and to produce some data (read from soundcard, download through HTTP,
  etc.) and send it through such pad. If the pad has the flow control set to
  `:manual`, then endpoint is also responsible for receiving demands on the output
  pad and requesting them on the input pad (for more details, see
  `c:Membrane.Element.WithOutputPads.handle_demand/5` callback).
  Endpoints, like all elements, can of course have multiple pads if needed to
  provide more complex solutions.
  """

  alias Membrane.Core.DocsHelper

  @doc """
  Brings all the stuff necessary to implement a endpoint element.

  Options:
    - `:bring_pad?` - if true (default) requires and aliases `Membrane.Pad`
    - `:flow_control_hints?` - if true (default) generates compile-time warnings \
      if the number, direction, and type of flow control of pads are likely to cause unintended \
      behaviours.
  """
  defmacro __using__(options) do
    Module.put_attribute(__CALLER__.module, :__membrane_element_type__, :endpoint)

    quote location: :keep do
      use Membrane.Element.Base, unquote(options)
      use Membrane.Element.WithOutputPads
      use Membrane.Element.WithInputPads

      @doc false
      @spec membrane_element_type() :: Membrane.Element.type()
      def membrane_element_type, do: :endpoint
    end
  end

  DocsHelper.add_callbacks_list_to_moduledoc(
    __MODULE__,
    [Membrane.Element.Base, Membrane.Element.WithInputPads, Membrane.Element.WithOutputPads]
  )
end
