defmodule Membrane.Element.CallbackContext.Demand do
  @moduledoc """
  Structure representing a context that is passed to the element
  when processing incoming demand.
  """

  @type t :: %Membrane.Element.CallbackContext.Demand{
          caps: Membrane.Caps.t()
        }

  defstruct caps: nil
end
