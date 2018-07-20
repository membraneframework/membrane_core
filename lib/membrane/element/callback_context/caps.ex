defmodule Membrane.Element.CallbackContext.Caps do
  @moduledoc """
  Structure representing a context that is passed to the element when receiving
  information about new caps for given pad
  """
  @behaviour Membrane.Element.CallbackContext

  @type t :: %__MODULE__{
          playback_state: Membrane.Core.Playback.state_t(),
          caps: Membrane.Caps.t() | nil
        }

  defstruct playback_state: nil, caps: nil

  @impl true
  defmacro from_state(state, entries) do
    quote do
      %unquote(__MODULE__){
        unquote_splicing(entries),
        playback_state: unquote(state).playback.state
      }
    end
  end
end
