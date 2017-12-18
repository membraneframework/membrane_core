defmodule Membrane.Element.Context.Write do
  @moduledoc """
  Structure representing a context that is passed to the element
  when new buffer arrives to the sink.
  """

  @type t :: %Membrane.Element.Context.Write{
    caps: Membrane.Caps.t
  }

  defstruct \
    caps: nil

end
