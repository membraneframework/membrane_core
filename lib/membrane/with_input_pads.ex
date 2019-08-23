defmodule Membrane.WithInputPads do
  @moduledoc """
  Module defining behaviour for sink and filter elements.

  When used declares behaviour implementation, provides default callback definitions
  and imports macros.

  For more information on implementing elements, see `Membrane.Element.Base`.
  """

  alias Membrane.{Element, Pad}
  alias Membrane.Core.PadsSpecs
  alias Element.CallbackContext

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
  Callback invoked when element receives `Membrane.Event.StartOfStream` event.
  """
  @callback handle_start_of_stream(
              pad :: Pad.ref_t(),
              context :: CallbackContext.StreamManagement.t(),
              state :: Element.state_t()
            ) :: CommonBehaviour.callback_return_t()

  @doc """
  Callback invoked when element receives `Membrane.Event.EndOfStream` event
  emitted when action `end_of_stream` is returned.
  """
  @callback handle_end_of_stream(
              pad :: Pad.ref_t(),
              context :: CallbackContext.StreamManagement.t(),
              state :: Element.state_t()
            ) :: CommonBehaviour.callback_return_t()

  @doc """
  Macro that defines multiple input pads for the element.

  Deprecated in favor of `def_input_pad/2`
  """
  @deprecated "Use def_input_pad/2 for each pad instead"
  defmacro def_input_pads(pads) do
    PadsSpecs.def_pads(pads, :input)
  end

  @doc PadsSpecs.def_pad_docs(:input, :element)
  defmacro def_input_pad(name, spec) do
    PadsSpecs.def_pad(name, :input, spec)
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      import unquote(__MODULE__), only: [def_input_pads: 1, def_input_pad: 2]

      @impl true
      def handle_caps(_pad, _caps, _context, state), do: {:ok, state}

      @impl true
      def handle_start_of_stream(pad, _context, state), do: {:ok, state}

      @impl true
      def handle_end_of_stream(pad, _context, state), do: {:ok, state}

      defoverridable handle_caps: 4,
                     handle_start_of_stream: 3,
                     handle_end_of_stream: 3
    end
  end
end
