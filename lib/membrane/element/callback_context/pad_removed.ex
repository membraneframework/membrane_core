defmodule Membrane.Element.CallbackContext.PadRemoved do
  @moduledoc """
  Structure representing a context that is passed to the element
  when a dynamic pad is removed
  """
  use Membrane.Core.Element.CallbackContext,
    direction: :input | :output
end
