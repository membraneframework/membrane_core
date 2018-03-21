defmodule Membrane.Element.Context.PadRemoved do
  @moduledoc """
  Structure representing a context that is passed to the element when
  when new pad added is created
  """

  @type t :: %Membrane.Element.Context.PadRemoved{
          direction: :sink | :source,
          caps: Membrane.Caps.t()
        }

  defstruct direction: nil,
            caps: nil
end
