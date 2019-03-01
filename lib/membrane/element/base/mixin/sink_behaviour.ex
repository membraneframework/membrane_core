defmodule Membrane.Element.Base.Mixin.SinkBehaviour do
  @moduledoc """
  Module defining behaviour for sink and filter elements.

  When used declares behaviour implementation, provides default callback definitions
  and imports macros.

  For more information on implementing elements, see `Membrane.Element.Base`.
  """

  alias Membrane.Element
  alias Membrane.Core.Element.PadsSpecsParser
  alias Element.{CallbackContext, Pad}
  alias Element.Base.Mixin.CommonBehaviour

  @doc """
  Callback invoked when Element is receiving information about new caps for
  given pad.

  In filters those caps are forwarded through all output pads by default.
  """
  @callback handle_caps(
              pad :: Pad.ref_t(),
              caps :: Membrane.Caps.t(),
              context :: CallbackContext.Caps.t(),
              state :: Element.state_t()
            ) :: CommonBehaviour.callback_return_t()

  @doc """
  Macro that defines input pads for the element.

  Allows to use `Membrane.Caps.Matcher.one_of/1` and `Membrane.Caps.Matcher.range/2`
  functions without module prefix.

  It automatically generates documentation from the given definition
  and adds compile-time caps specs validation.

  The type `t:Membrane.Element.Pad.input_spec_t/0` describes how the definition of pads should look.
  """
  @deprecated "Use def_input_pad/2 for each pad instead"
  defmacro def_input_pads(pads) do
    PadsSpecsParser.def_pads(pads, :input)
  end

  defmacro def_input_pad(name, spec) do
    PadsSpecsParser.def_pad(name, :input, spec)
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      import unquote(__MODULE__), only: [def_input_pads: 1, def_input_pad: 2]

      @impl true
      def handle_caps(_pad, _caps, _context, state), do: {:ok, state}

      defoverridable handle_caps: 4
    end
  end
end
