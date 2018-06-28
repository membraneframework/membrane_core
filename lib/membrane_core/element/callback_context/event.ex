defmodule Membrane.Element.CallbackContext.Event do
  @moduledoc """
  Structure representing a context that is passed to the element
  when handling event.
  """
  @behaviour Membrane.Element.CallbackContext

  @type t :: %Membrane.Element.CallbackContext.Event{
          playback_state: Membrane.Mixins.Playback.state_t(),
          caps: Membrane.Caps.t()
        }

  defstruct playback_state: nil, caps: nil

  @impl true
  def from_state(state, entries) do
    common = [playback_state: state.playback.state]
    struct!(__MODULE__, entries ++ common)
  end
end
