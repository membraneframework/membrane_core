defmodule Membrane.Core.Element.CallbackContext do
  @moduledoc false

  use Membrane.Core.CallbackContext,
    pads: %{Membrane.Pad.ref_t() => Membrane.Element.PadData.t()},
    clock: Membrane.Clock.t() | nil,
    parent_clock: Membrane.Clock.t() | nil,
    name: Membrane.Element.name_t(),
    playback: Membrane.Playback.t()

  @impl true
  def extract_default_fields(state, args) do
    quote do
      [
        pads: unquote(state).pads_data,
        clock: unquote(state).synchronization.clock,
        parent_clock: unquote(state).synchronization.parent_clock,
        name: unquote(state).name,
        playback: unquote(state).playback
      ]
    end ++ args
  end
end
