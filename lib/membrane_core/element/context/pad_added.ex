defmodule Membrane.Element.Context.PadAdded do
  @moduledoc """
  Structure representing a context that is passed to the element when
  when new pad added is created
  """

  @type t :: %Membrane.Element.Context.PadAdded{
          direction: :sink | :source
        }

  defstruct direction: nil
end
