defmodule Membrane.Element.CallbackContext.Other do
  @moduledoc """
  Structure representing a context that is passed to the callback when
  element receives unrecognized message.
  """
  @behaviour Membrane.Element.CallbackContext

  @type t :: %__MODULE__{
          playback_state: Membrane.Mixins.Playback.state_t()
        }

  defstruct playback_state: nil

  @impl true
  def from_state(state, entries \\ []) do
    common = [playback_state: state.playback.state]
    struct!(__MODULE__, entries ++ common)
  end
end
