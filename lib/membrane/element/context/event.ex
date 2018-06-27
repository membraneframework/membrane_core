defmodule Membrane.Element.Context.Event do
  @moduledoc """
  Structure representing a context that is passed to the element
  when handling event.
  """

  @type t :: %Membrane.Element.Context.Event{
          caps: Membrane.Caps.t()
        }

  defstruct caps: nil
end
