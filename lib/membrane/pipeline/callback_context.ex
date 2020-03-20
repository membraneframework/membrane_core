defmodule Membrane.Pipeline.CallbackContext do
  use Membrane.CallbackContext

  @impl true
  def default_fields_names() do
    [
      :playback_state,
      :clock
    ]
  end

  @impl true
  def default_ctx_assigment(state) do
    quote do
      [
        playback_state: unquote(state).playback.state,
        clock: unquote(state).clock_provider.clock
      ]
    end
  end
end
