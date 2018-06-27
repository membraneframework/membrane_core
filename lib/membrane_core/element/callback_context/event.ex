defmodule Membrane.Element.CallbackContext.Event do
  @moduledoc """
  Structure representing a context that is passed to the element
  when handling event.
  """

  @type t :: %Membrane.Element.CallbackContext.Event{
          caps: Membrane.Caps.t()
        }

  defstruct caps: nil
end
