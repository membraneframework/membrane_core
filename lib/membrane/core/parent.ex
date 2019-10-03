defmodule Membrane.Core.Parent do
  alias Membrane.Core.Message

  require Membrane.PlaybackState
  require Message

  # TODO This is something more general, probably should be moved to PlaybackHandler ?
  @spec change_playback_state(pid, Membrane.PlaybackState.t()) :: :ok
  def change_playback_state(pid, new_state)
      when Membrane.PlaybackState.is_playback_state(new_state) do
    Message.send(pid, :change_playback_state, new_state)
    :ok
  end
end
