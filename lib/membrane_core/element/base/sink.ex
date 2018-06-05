defmodule Membrane.Element.Base.Sink do
  @moduledoc """
  Module defining behaviour for sinks - elements consuming data.

  Behaviours for filters are specified, besides this place, in modules
  `Membrane.Element.Base.Mixin.CommonBehaviour`,
  and `Membrane.Element.Base.Mixin.SinkBehaviour`.

  Sink elements can define only sink pads. Job of a usual sink is to receive some
  data on such pad and consume it (write to a soundcard, send through TCP etc.).
  If the pad works in pull mode, which is the most common case, then element is
  also responsible for requesting demands when it is able and willing to consume
  data (for more details, see `t:Membrane.Element.Action.demand_t/0`).
  Sinks, like all elements, can of course have multiple pads if needed to
  provide more complex solutions.
  """

  alias Membrane.{Buffer, Element}
  alias Element.Base.Mixin
  alias Element.{Context, Pad}
  alias Element.Manager.State

  @doc """
  Callback that is called when buffer should be written by the sink.

  For pads in pull mode it is called when buffers have been demanded (by returning
  `:demand` action from any callback).

  For pads in push mode it is invoked when buffers arrive.
  """
  @callback handle_write(
              pad :: Pad.name_t(),
              buffers :: list(Buffer.t()),
              context :: Context.Write.t(),
              state :: State.internal_state_t()
            ) :: Mixin.CommonBehaviour.callback_return_t()

  @doc """
  Callback that is called when buffer should be written by the sink. In contrast
  to `c:handle_write/4`, it is passed only a single buffer.

  Called by default implementation of `c:handle_write/4`.
  """
  @callback handle_write1(
              pad :: Pad.name_t(),
              buffer :: Buffer.t(),
              context :: Context.Write.t(),
              state :: State.internal_state_t()
            ) :: Mixin.CommonBehaviour.callback_return_t()

  defmacro __using__(_) do
    quote location: :keep do
      use Mixin.CommonBehaviour
      use Mixin.SinkBehaviour
      @behaviour unquote(__MODULE__)

      @impl true
      def manager_module, do: Membrane.Element.Manager.Sink

      @impl true
      def handle_write1(_pad, _buffer, _context, state),
        do: {{:error, :handle_write_not_implemented}, state}

      @impl true
      def handle_write(pad, buffers, context, state) do
        args_list = buffers |> Enum.map(&[pad, &1, context])
        {{:ok, split: {:handle_write1, args_list}}, state}
      end

      defoverridable handle_write: 4,
                     handle_write1: 4
    end
  end
end
