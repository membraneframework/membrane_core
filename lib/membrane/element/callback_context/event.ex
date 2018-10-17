defmodule Membrane.Element.CallbackContext.Event do
  @moduledoc """
  Structure representing a context that is passed to the element
  when handling event.
  """
  use Membrane.Element.CallbackContext,
    caps: Membrane.Caps.t()
end
