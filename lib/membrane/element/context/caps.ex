defmodule Membrane.Element.Context.Caps do
  @moduledoc """
  Structure representing a context that is passed to the element when receiving
  information about new caps for given pad
  """

  @type t :: %Membrane.Element.Context.Caps{
          caps: Membrane.Caps.t() | nil
        }

  defstruct caps: nil
end
