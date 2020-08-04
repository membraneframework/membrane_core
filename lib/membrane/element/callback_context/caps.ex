defmodule Membrane.Element.CallbackContext.Caps do
  @moduledoc """
  Structure representing a context that is passed to the element when receiving
  information about new caps for given pad.

  The `old_caps` field contains caps previously present on the pad, and is equal
  to `pads[pad].caps` field.
  """

  use Membrane.Core.Element.CallbackContext,
    old_caps: Membrane.Caps.t()

  alias Membrane.Core.Child.PadModel

  @impl true
  defmacro from_state(state, args) do
    {pad, args} = args |> Keyword.pop(:pad)

    old_caps =
      quote do
        unquote(state) |> PadModel.get_data!(unquote(pad), :caps)
      end

    super(state, args ++ [old_caps: old_caps])
  end
end
