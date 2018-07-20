defmodule Membrane.Element.CallbackContext.Other do
  @moduledoc """
  Structure representing a context that is passed to the callback when
  element receives unrecognized message.
  """
  @behaviour Membrane.Element.CallbackContext

  @type t :: %__MODULE__{
          playback_state: Membrane.Core.Playback.state_t()
        }

  defstruct playback_state: nil

  @impl true
  defmacro from_state(state, entries \\ []) do
    quote do
      %unquote(__MODULE__){
        unquote_splicing(entries),
        playback_state: unquote(state).playback.state
      }
    end
  end
end
