defmodule Membrane.Element.Base.Filter do
  @moduledoc """
  Module defining behaviour for filters - elements processing data.

  Behaviours for filters are specified, besides this place, in modules
  `Membrane.Element.Base.Mixin.CommonBehaviour`,
  `Membrane.Element.Base.Mixin.SourceBehaviour`,
  and `Membrane.Element.Base.Mixin.SinkBehaviour`.

  Filters can have both sink and source pads. Job of a usual filter is to
  receive some data on a sink pad, process the data and send it through the
  source pad. If these pads work in pull mode, which is the most common case,
  then filter is also responsible for receiving demands on the source pad and
  requesting them on the sink pad (for more details, see
  `c:Membrane.Element.Base.Mixin.SourceBehaviour.handle_demand/5` callback).
  Filters, like all elements, can of course have multiple pads if needed to
  provide more complex solutions.
  """

  alias Membrane.{Buffer, Element}
  alias Element.Base.Mixin
  alias Element.{Context, Pad}

  @doc """
  Callback that is to process buffers.

  For pads in pull mode it is called when buffers have been demanded (by returning
  `:demand` action from any callback).

  For pads in push mode it is invoked when buffers arrive.
  """
  @callback handle_process(
              pad :: Pad.name_t(),
              buffers :: list(Buffer.t()),
              context :: Context.Process.t(),
              state :: Mixin.CommonBehaviour.internal_state_t()
            ) :: Mixin.CommonBehaviour.callback_return_t()

  @doc """
  Callback that is to process buffers. In contrast to `c:handle_process/4`, it is
  passed only a single buffer.

  Called by default implementation of `c:handle_process/4`.
  """
  @callback handle_process1(
              pad :: Pad.name_t(),
              buffer :: Buffer.t(),
              context :: Context.Process.t(),
              state :: Mixin.CommonBehaviour.internal_state_t()
            ) :: Mixin.CommonBehaviour.callback_return_t()

  defmacro __using__(_) do
    quote location: :keep do
      use Mixin.CommonBehaviour
      use Mixin.SourceBehaviour
      use Mixin.SinkBehaviour
      @behaviour unquote(__MODULE__)

      @impl true
      def membrane_element_type, do: :filter

      @impl true
      def handle_caps(_pad, caps, _context, state), do: {{:ok, forward: caps}, state}

      @impl true
      def handle_event(_pad, event, _context, state), do: {{:ok, forward: event}, state}

      @impl true
      def handle_demand(_pad, _size, _unit, _context, state),
        do: {{:error, :handle_demand_not_implemented}, state}

      @impl true
      def handle_process1(_pad, _buffer, _context, state),
        do: {{:error, :handle_process_not_implemented}, state}

      @impl true
      def handle_process(pad, buffers, context, state) do
        args_list = buffers |> Enum.map(&[pad, &1, context])
        {{:ok, split: {:handle_process1, args_list}}, state}
      end

      defoverridable handle_caps: 4,
                     handle_event: 4,
                     handle_demand: 5,
                     handle_process: 4,
                     handle_process1: 4
    end
  end
end
