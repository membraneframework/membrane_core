defmodule Membrane.Element.Context.Other do
  @moduledoc """
  Structure representing a context that is passed to the callback when
  element receives unrecognized message.
  """

  @type t :: %__MODULE__{}

  defstruct []
end
