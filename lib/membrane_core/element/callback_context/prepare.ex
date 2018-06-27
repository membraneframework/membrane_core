defmodule Membrane.Element.CallbackContext.Prepare do
  @moduledoc """
  Structure representing a context that is passed to the callback of the element
  when it goes into `:prepared` state.
  """

  @type t :: %__MODULE__{}

  defstruct []
end
