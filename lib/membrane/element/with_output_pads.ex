defmodule Membrane.Element.WithOutputPads do
  @moduledoc """
  Module defining behaviour for source and filter elements.

  When used declares behaviour implementation, provides default callback definitions
  and imports macros.

  For more information on implementing elements, see `Membrane.Element.Base`.
  """

  alias Membrane.{Buffer, Element, Pad}
  alias Membrane.Core.CallbackHandler
  alias Membrane.Core.Child.PadsSpecs
  alias Membrane.Element.CallbackContext

  @doc """
  Callback called when buffers should be emitted by a source or filter.

  It is called only for output pads in the pull mode, as in their case demand
  is triggered by the input pad of the subsequent element.

  In sources, appropriate amount of data should be sent here.

  In filters, this callback should usually return `:demand` action with
  size sufficient for supplying incoming demand. This will result in calling
  `c:Membrane.Filter.handle_process_list/4`, which is to supply
  the demand.

  If a source is unable to produce enough buffers, or a filter underestimated
  returned demand, the `:redemand` action should be used (see
  `t:Membrane.Element.Action.redemand_t/0`).
  """
  @callback handle_demand(
              pad :: Pad.ref_t(),
              size :: non_neg_integer,
              unit :: Buffer.Metric.unit_t(),
              context :: CallbackContext.Demand.t(),
              state :: Element.state_t()
            ) :: CallbackHandler.callback_return_t()

  @optional_callbacks handle_demand: 5

  @doc """
  Macro that defines multiple output pads for the element.

  Deprecated in favor of `def_output_pad/2`
  """
  @deprecated "Use `def_output_pad/2 for each pad instead"
  defmacro def_output_pads(pads) do
    PadsSpecs.def_pads(pads, :output, :element)
  end

  @doc PadsSpecs.def_pad_docs(:output, :element)
  defmacro def_output_pad(name, spec) do
    PadsSpecs.def_pad(name, :output, spec, :element)
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      import unquote(__MODULE__), only: [def_output_pads: 1, def_output_pad: 2]

      @impl true
      def handle_demand(_pad, _size, _unit, _context, state),
        do: {{:error, :handle_demand_not_implemented}, state}

      defoverridable handle_demand: 5
    end
  end
end
