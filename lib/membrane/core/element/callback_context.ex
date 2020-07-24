defmodule Membrane.Core.Element.CallbackContext do
  @moduledoc false

  use Membrane.Core.CallbackContext,
    pads: %{Membrane.Pad.ref_t() => Membrane.Pad.Data.t()},
    playback_state: Membrane.PlaybackState.t(),
    clock: Membrane.Clock.t() | nil,
    parent_clock: Membrane.Clock.t() | nil,
    name: Membrane.Element.name_t()

  @impl true
  def extract_default_fields(state, args) do
    quote do
      [
        playback_state: unquote(state).playback.state,
        pads: unquote(state).pads.data,
        clock: unquote(state).synchronization.clock,
        parent_clock: unquote(state).synchronization.parent_clock,
        name: unquote(state).name
      ]
    end ++ args
  end
end
