defmodule Membrane.Pipeline.CallbackContext do
  use Membrane.CallbackContext,
    playback_state: Membrane.PlaybackState.t(),
    clock: Membrane.Clock.t()

  @impl true
  def extract_default_fields(state, args) do
    quote do
      [
        playback_state: unquote(state).playback.state,
        clock: unquote(state).clock_provider.clock
      ]
    end ++ args
  end
end
