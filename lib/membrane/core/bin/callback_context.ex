defmodule Membrane.Core.Bin.CallbackContext do
  @moduledoc false

  use Membrane.Core.CallbackContext,
    playback_state: Membrane.PlaybackState.t(),
    clock: Membrane.Clock.t(),
    parent_clock: Membrane.Clock.t(),
    pads: %{Membrane.Pad.ref_t() => Membrane.Pad.Data.t()},
    name: Membrane.Bin.name_t(),
    children: %{Membrane.Child.name_t() => Membrane.ChildEntry.t()}

  @impl true
  def extract_default_fields(state, args) do
    quote do
      [
        playback_state: unquote(state).playback.state,
        clock: unquote(state).synchronization.clock,
        parent_clock: unquote(state).synchronization.parent_clock,
        pads: unquote(state).pads.data,
        name: unquote(state).name,
        children: unquote(state).children
      ]
    end ++ args
  end
end
