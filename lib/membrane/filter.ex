defmodule Membrane.Filter do
  @moduledoc """
  Module defining behaviour for filters - elements processing data.

  Behaviours for filters are specified, besides this place, in modules
  `Membrane.Element.Base`,
  `Membrane.Element.WithOutputPads`,
  and `Membrane.Element.WithInputPads`.

  Filters can have both input and output pads. Job of a usual filter is to
  receive some data on a input pad, process the data and send it through the
  output pad. If the pad has the flow control set to `:manual`, then filter
  is also responsible for receiving demands on the output pad and requesting
  them on the input pad (for more details, see
  `c:Membrane.Element.WithOutputPads.handle_demand/5` callback).
  Filters, like all elements, can of course have multiple pads if needed to
  provide more complex solutions.
  """

  alias Membrane.Core.DocsHelper

  @doc """
  Brings all the stuff necessary to implement a filter element.

  Options:
    - `:bring_pad?` - if true (default) requires and aliases `Membrane.Pad`
  """

  defmacro __using__(options) do
    Module.put_attribute(__CALLER__.module, :__membrane_element_type__, :filter)

    quote location: :keep do
      use Membrane.Element.Base, unquote(options)
      use Membrane.Element.WithOutputPads
      use Membrane.Element.WithInputPads

      @doc false
      @spec membrane_element_type() :: Membrane.Element.type()
      def membrane_element_type, do: :filter

      @impl true
      def handle_stream_format(_pad, stream_format, _context, state) do
        {[forward: stream_format], state}
      end

      @impl true
      def handle_event(_pad, event, _context, state) do
        {[forward: event], state}
      end

      @impl true
      def handle_end_of_stream(pad, _context, state) do
        {[forward: :end_of_stream], state}
      end

      @impl true
      def handle_buffer(pad, buffer, ctx, state) do
        apply(__MODULE__, :handle_write, [pad, buffer, ctx, state])
      end

      @impl true
      def handle_buffers_batch(pad, buffers, ctx, state) do
        apply(__MODULE__, :handle_write_list, [pad, buffers, ctx, state])
      end

      @impl true
      def handle_write_list(pad, buffers, ctx, state) do
        args_list = buffers |> Enum.map(&[pad, &1])
        {[split: {:handle_buffer, args_list}], state}
      end

      defoverridable handle_stream_format: 4,
                     handle_event: 4,
                     handle_end_of_stream: 3,
                     handle_buffer: 4,
                     handle_buffers_batch: 4,
                     handle_write_list: 4
    end
  end

  DocsHelper.add_callbacks_list_to_moduledoc(
    __MODULE__,
    [Membrane.Element.Base, Membrane.Element.WithInputPads, Membrane.Element.WithOutputPads]
  )
end
