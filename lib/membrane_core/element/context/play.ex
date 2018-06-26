defmodule Membrane.Element.Context.Play do
  @moduledoc """
  Structure representing a context that is passed to the callback of the element
  when it goes into `:playing` state.
  """

  @type t :: %__MODULE__{}

  defstruct []
end
