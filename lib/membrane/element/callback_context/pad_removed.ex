defmodule Membrane.Element.CallbackContext.PadRemoved do
  @moduledoc """
  Structure representing a context that is passed to the element when
  when new pad added is created
  """
  @behaviour Membrane.Element.CallbackContext

  @type t :: %Membrane.Element.CallbackContext.PadRemoved{
          playback_state: Membrane.Mixins.Playback.state_t(),
          direction: :sink | :source,
          caps: Membrane.Caps.t()
        }

  defstruct playback_state: nil,
            direction: nil,
            caps: nil

  @impl true
  def from_state(state, entries) do
    common = [playback_state: state.playback.state]
    struct!(__MODULE__, Enum.concat(entries, common))
  end
end
