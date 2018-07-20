defmodule Membrane.Element.CallbackContext.Prepare do
  @moduledoc """
  Structure representing a context that is passed to the callback of the element
  when it goes into `:prepared` state.
  """
  @behaviour Membrane.Element.CallbackContext

  @type t :: %__MODULE__{}

  defstruct []

  @impl true
  defmacro from_state(_state, entries \\ []) do
    quote do
      %unquote(__MODULE__){
        unquote_splicing(entries)
      }
    end
  end
end
