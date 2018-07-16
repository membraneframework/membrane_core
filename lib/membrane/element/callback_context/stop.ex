defmodule Membrane.Element.CallbackContext.Stop do
  @moduledoc """
  Structure representing a context that is passed to the callback of the element
  when it goes into `:stopped` state.
  """
  @behaviour Membrane.Element.CallbackContext

  @type t :: %__MODULE__{}

  defstruct []

  @impl true
  def from_state(_state, entries) do
    struct!(__MODULE__, entries)
  end
end
