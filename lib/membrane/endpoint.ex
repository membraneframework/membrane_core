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
  etc.) and send it through such pad. If these pads work in pull mode, which is
  the most common case, then endpoint is also responsible for receiving demands on
  the output pad and requesting them on the input pad (for more details, see
  `c:Membrane.Element.WithOutputPads.handle_demand/5` callback).
  Endpoints, like all elements, can of course have multiple pads if needed to
  provide more complex solutions.
  """

  alias Membrane.{Buffer, Element, Pad}
  alias Membrane.Core.DocsHelper
  alias Membrane.Element.CallbackContext

  @doc """
  Callback that is called when buffer should be written by the endpoint.

  By default calls `c:handle_write/4` for each buffer.

  For pads in pull mode it is called when buffers have been demanded (by returning
  `:demand` action from any callback).

  For pads in push mode it is invoked when buffers arrive.
  """
  @callback handle_write_list(
              pad :: Pad.ref_t(),
              buffers :: list(Buffer.t()),
              context :: CallbackContext.Process.t(),
              state :: Element.state_t()
            ) :: Membrane.Element.Base.callback_return_t()

  @doc """
  Callback that is called when buffer should be written by the endpoint. In contrast
  to `c:handle_write_list/4`, it is passed only a single buffer.

  Called by default implementation of `c:handle_write_list/4`.
  """
  @callback handle_write(
              pad :: Pad.ref_t(),
              buffer :: Buffer.t(),
              context :: CallbackContext.Process.t(),
              state :: Element.state_t()
            ) :: Membrane.Element.Base.callback_return_t()

  @optional_callbacks handle_write: 4

  @doc """
  Brings all the stuff necessary to implement a endpoint element.

  Options:
    - `:bring_pad?` - if true (default) requires and aliases `Membrane.Pad`
  """
  defmacro __using__(options) do
    quote location: :keep do
      use Membrane.Element.Base, unquote(options)
      use Membrane.Element.WithOutputPads
      use Membrane.Element.WithInputPads

      @behaviour unquote(__MODULE__)

      @doc false
      @spec membrane_element_type() :: Membrane.Element.type_t()
      def membrane_element_type, do: :endpoint

      @impl true
      def handle_write_list(pad, buffers, _context, state) do
        args_list = buffers |> Enum.map(&[pad, &1])
        {[split: {:handle_write, args_list}], state}
      end

      defoverridable handle_write_list: 4
    end
  end

  DocsHelper.add_callbacks_list_to_moduledoc(
    __MODULE__,
    [Membrane.Element.Base, Membrane.Element.WithInputPads, Membrane.Element.WithOutputPads]
  )
end
