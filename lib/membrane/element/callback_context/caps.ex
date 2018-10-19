defmodule Membrane.Element.CallbackContext.Caps do
  @moduledoc """
  Structure representing a context that is passed to the element when receiving
  information about new caps for given pad.

  The `pads[pad].caps` field is set to the old caps and has the same value as
  the `old_caps` field.
  """
  use Membrane.Element.CallbackContext,
    old_caps: Membrane.Caps.t()
end
