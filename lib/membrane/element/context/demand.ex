defmodule Membrane.Element.Context.Demand do
  @moduledoc """
  Structure representing a context that is passed to the element
  when processing incoming demand.
  """

  @type t :: %Membrane.Element.Context.Demand{
          caps: Membrane.Caps.t()
        }

  defstruct caps: nil
end
