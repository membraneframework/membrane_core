defmodule Membrane.Element.CallbackContext.Write do
  @moduledoc """
  Structure representing a context that is passed to the element
  when new buffer arrives to the sink.
  """

  @type t :: %Membrane.Element.CallbackContext.Write{
          caps: Membrane.Caps.t()
        }

  defstruct caps: nil
end
