defmodule Membrane.Element.CallbackContext do
  alias Membrane.Pad
  use Membrane.CallbackContext

  @impl true
  def default_fields_names() do
    [
      :pads,
      :playback_state,
      :clock,
      :parent_clock
    ]
  end

  @impl true
  def default_ctx_assigment(state) do
    quote do
      [
        playback_state: unquote(state).playback.state,
        pads: unquote(state).pads.data,
        clock: unquote(state).synchronization.clock,
        parent_clock: unquote(state).synchronization.parent_clock
      ]
    end
  end
end
