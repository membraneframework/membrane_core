defmodule Membrane.Element.CallbackContext.Stop do
  @moduledoc """
  Structure representing a context that is passed to the callback of the element
  when it goes into `:stopped` state.
  """

  @type t :: %__MODULE__{}

  defstruct []
end
