defmodule Membrane.Element.CallbackContext.Caps do
  @moduledoc """
  Structure representing a context that is passed to the element when receiving
  information about new caps for given pad
  """

  @type t :: %Membrane.Element.CallbackContext.Caps{
          caps: Membrane.Caps.t() | nil
        }

  defstruct caps: nil
end
