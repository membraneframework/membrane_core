defmodule Membrane.Bin.CallbackContext do
  use Membrane.CallbackContext

  @impl true
  def default_fields_names() do
    [
      :playback_state,
      :clock,
      :pads,
      :name
    ]
  end

  @impl true
  def default_ctx_assigment(state) do
    quote do
      [
        playback_state: unquote(state).playback.state,
        clock: unquote(state).clock_provider.clock,
        pads: unquote(state).pads.data,
        name: unquote(state).name
      ]
    end
  end
end
