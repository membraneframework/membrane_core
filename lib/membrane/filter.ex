defmodule Membrane.Filter do
  @moduledoc """
  Module defining behaviour for filters - elements processing data.

  Behaviours for filters are specified, besides this place, in modules
  `Membrane.Element.Base`,
  `Membrane.Element.WithOutputPads`,
  and `Membrane.Element.WithInputPads`.

  Filters can have both input and output pads. Job of a usual filter is to
  receive some data on a input pad, process the data and send it through the
  output pad. If these pads work in pull mode, which is the most common case,
  then filter is also responsible for receiving demands on the output pad and
  requesting them on the input pad (for more details, see
  `c:Membrane.Element.WithOutputPads.handle_demand/5` callback).
  Filters, like all elements, can of course have multiple pads if needed to
  provide more complex solutions.
  """

  alias Membrane.{Buffer, Element, Pad}
  alias Membrane.Core.DocsHelper
  alias Membrane.Element.CallbackContext

  @doc """
  Callback that is to process buffers.

  By default calls `c:handle_process/4` for each buffer.

  For pads in pull mode it is called when buffers have been demanded (by returning
  `:demand` action from any callback).

  For pads in push mode it is invoked when buffers arrive.
  """
  @callback handle_process_list(
              pad :: Pad.ref_t(),
              buffers :: list(Buffer.t()),
              context :: CallbackContext.Process.t(),
              state :: Element.state_t()
            ) :: Membrane.Element.Base.callback_return_t()

  @doc """
  Callback that is to process buffers. In contrast to `c:handle_process_list/4`, it is
  passed only a single buffer.

  Called by default implementation of `c:handle_process_list/4`.
  """
  @callback handle_process(
              pad :: Pad.ref_t(),
              buffer :: Buffer.t(),
              context :: CallbackContext.Process.t(),
              state :: Element.state_t()
            ) :: Membrane.Element.Base.callback_return_t()

  @optional_callbacks handle_process: 4

  @doc """
  Brings all the stuff necessary to implement a filter element.

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
      def membrane_element_type, do: :filter

      @impl true
      def handle_stream_format(_pad, stream_format, _context, state),
        do: {[forward: stream_format], state}

      @impl true
      def handle_event(_pad, event, _context, state), do: {[forward: event], state}

      @impl true
      def handle_process_list(pad, buffers, _context, state) do
        args_list = buffers |> Enum.map(&[pad, &1])
        {[split: {:handle_process, args_list}], state}
      end

      @impl true
      def handle_end_of_stream(pad, _context, state),
        do: {[forward: :end_of_stream], state}

      defoverridable handle_stream_format: 4,
                     handle_event: 4,
                     handle_process_list: 4,
                     handle_end_of_stream: 3
    end
  end

  DocsHelper.add_callbacks_list_to_moduledoc(
    __MODULE__,
    [Membrane.Element.Base, Membrane.Element.WithInputPads, Membrane.Element.WithOutputPads]
  )
end
