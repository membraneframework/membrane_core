defmodule Membrane.Element.WithInputPads do
  @moduledoc """
  Module defining behaviour for sink, filter and endpoint elements.

  When used declares behaviour implementation, provides default callback definitions
  and imports macros.

  For more information on implementing elements, see `Membrane.Element.Base`.
  """

  alias Membrane.Core.Child.PadsSpecs
  alias Membrane.{Element, Pad}
  alias Membrane.Element.CallbackContext

  @doc """
  Callback invoked when Element is receiving information about new stream format for
  given pad.

  In filters stream format is forwarded through all output pads by default.
  """
  @callback handle_stream_format(
              pad :: Pad.ref_t(),
              stream_format :: Membrane.StreamFormat.t(),
              context :: CallbackContext.StreamFormat.t(),
              state :: Element.state_t()
            ) :: Membrane.Element.Base.callback_return_t()

  @optional_callbacks handle_stream_format: 4

  @doc """
  Callback invoked when element receives `Membrane.Event.StartOfStream` event.
  """
  @callback handle_start_of_stream(
              pad :: Pad.ref_t(),
              context :: CallbackContext.StreamManagement.t(),
              state :: Element.state_t()
            ) :: Membrane.Element.Base.callback_return_t()

  @doc """
  Callback invoked when the previous element has finished processing via the pad,
  and it cannot be used anymore.
  """
  @callback handle_end_of_stream(
              pad :: Pad.ref_t(),
              context :: CallbackContext.StreamManagement.t(),
              state :: Element.state_t()
            ) :: Membrane.Element.Base.callback_return_t()

  @doc PadsSpecs.def_pad_docs(:input, :element)
  defmacro def_input_pad(name, spec) do
    PadsSpecs.def_pad(name, :input, spec, :element)
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      import unquote(__MODULE__), only: [def_input_pad: 2]

      @impl true
      def handle_stream_format(_pad, _stream_format, _context, state), do: {[], state}

      @impl true
      def handle_start_of_stream(pad, _context, state), do: {[], state}

      @impl true
      def handle_end_of_stream(pad, _context, state), do: {[], state}

      defoverridable handle_stream_format: 4,
                     handle_start_of_stream: 3,
                     handle_end_of_stream: 3
    end
  end
end
