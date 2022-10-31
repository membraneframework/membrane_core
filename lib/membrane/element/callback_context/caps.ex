defmodule Membrane.Element.CallbackContext.StreamFormat do
  @moduledoc """
  Structure representing a context that is passed to the element when receiving
  information about new stream format for given pad.

  The `old_stream_format` field contains stream format previously present on the pad, and is equal
  to `pads[pad].stream_format` field.
  """

  use Membrane.Core.Element.CallbackContext,
    old_stream_format: Membrane.StreamFormat.t()

  alias Membrane.Core.Child.PadModel

  @impl true
  defmacro from_state(state, args) do
    {pad, args} = args |> Keyword.pop(:pad)

    old_stream_format =
      quote do
        unquote(state) |> PadModel.get_data!(unquote(pad), :stream_format)
      end

    super(state, args ++ [old_stream_format: old_stream_format])
  end
end
