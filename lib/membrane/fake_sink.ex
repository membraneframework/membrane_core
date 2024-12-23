defmodule Membrane.Fake.Sink do
  @moduledoc """
  Membrane Sink that ignores incoming data.
  """

  use Membrane.Sink

  def_input_pad :input, accepted_format: _any

  @impl true
  def handle_buffer(:input, _buffer, _ctx, state), do: {[], state}
end
