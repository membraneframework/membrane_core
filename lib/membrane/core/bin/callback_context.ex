defmodule Membrane.Core.Bin.CallbackContext do
  @moduledoc false

  use Membrane.Core.CallbackContext,
    playback_state: Membrane.PlaybackState.t(),
    clock: Membrane.Clock.t() | nil,
    pads: %{Membrane.Pad.ref_t() => Membrane.Pad.Data.t()},
    name: Membrane.Bin.name_t()

  @impl true
  def extract_default_fields(state, args) do
    quote do
      [
        playback_state: unquote(state).playback.state,
        clock: unquote(state).clock_provider.clock,
        pads: unquote(state).pads.data,
        name: unquote(state).name
      ]
    end ++ args
  end
end
