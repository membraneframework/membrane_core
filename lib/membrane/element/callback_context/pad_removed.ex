defmodule Membrane.Element.CallbackContext.PadRemoved do
  @moduledoc """
  Structure representing a context that is passed to the element when
  when new pad added is created
  """
  use Membrane.Element.CallbackContext,
    direction: :input | :output
end
