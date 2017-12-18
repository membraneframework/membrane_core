defmodule Membrane.Element.Context.Caps do
  @moduledoc """
  Structure representing a context that is passed to the element when receiving
  information about new caps for given pad
  """

  @type t :: %Membrane.Element.Context.Caps{
    old_caps: Membrane.Caps.t | nil
  }

  defstruct \
    old_caps: nil

end
