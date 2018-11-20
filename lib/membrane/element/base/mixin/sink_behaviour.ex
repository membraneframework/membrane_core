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
  Macro that defines known input pads for the element type.

  Allows to use `Membrane.Caps.Matcher.one_of/1` and `Membrane.Caps.Matcher.range/2`
  functions without module prefix.

  It automatically generates documentation from the given definition
  and adds compile-time caps specs validation.

  The definition of pads should be a keyword list with pad name as key and
  another keyword list as a value. The inner list may contain the following entries:
  * `availability:` `t:Membrane.Element.Pad.availability_t/0` - defaults to `:always`,
  * `mode:` `t:Membrane.Element.Pad.mode_t/0`, defaults to `:pull`,
  * `demand_unit:` `t:Membrane.Buffer.Metric.unit_t/0`, required if mode is set to `pull`,
  * `caps:` `t:Membrane.Caps.Matcher.caps_specs_t/0` - always required, should contain the specification
    of allowed caps. See `Membrane.Caps.Matcher` for details on how to define it.
  """
  defmacro def_input_pads(pads) do
    PadsSpecsParser.def_pads(pads, :input)
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      import unquote(__MODULE__), only: [def_input_pads: 1]

      @impl true
      def handle_caps(_pad, _caps, _context, state), do: {:ok, state}

      defoverridable handle_caps: 4
    end
  end
end
