defmodule Membrane.Element.CallbackContext.Caps do
  @moduledoc """
  Structure representing a context that is passed to the element when receiving
  information about new caps for given pad
  """
  @behaviour Membrane.Element.CallbackContext

  @type t :: %__MODULE__{
          playback_state: Membrane.Mixins.Playback.state_t(),
          caps: Membrane.Caps.t() | nil
        }

  defstruct playback_state: nil, caps: nil

  @impl true
  def from_state(state, entries) do
    common = [playback_state: state.playback.state]
    struct!(__MODULE__, entries ++ common)
  end
end
