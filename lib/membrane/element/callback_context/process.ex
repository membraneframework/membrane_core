defmodule Membrane.Element.CallbackContext.Process do
  @moduledoc """
  Structure representing a context that is passed to the element when new buffer arrives.
  """
  @behaviour Membrane.Element.CallbackContext

  @type t :: %Membrane.Element.CallbackContext.Process{
          playback_state: Membrane.Mixins.Playback.state_t(),
          caps: Membrane.Caps.t(),
          source: nil,
          source_caps: Membrane.Caps.t()
        }

  defstruct playback_state: nil,
            caps: nil,
            source: nil,
            source_caps: nil

  @impl true
  def from_state(state, entries) do
    common = [playback_state: state.playback.state]
    struct!(__MODULE__, Enum.concat(entries, common))
  end
end
