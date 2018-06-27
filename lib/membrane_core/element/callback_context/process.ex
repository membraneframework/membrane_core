defmodule Membrane.Element.CallbackContext.Process do
  @moduledoc """
  Structure representing a context that is passed to the element when new buffer arrives.
  """

  @type t :: %Membrane.Element.CallbackContext.Process{
          caps: Membrane.Caps.t(),
          source: nil,
          source_caps: Membrane.Caps.t()
        }

  defstruct caps: nil,
            source: nil,
            source_caps: nil
end
