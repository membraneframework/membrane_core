defmodule Membrane.Core.Events.StartOfStream do
  @moduledoc false
  # Generated before processing the first buffer.
  # Invokes `c:Membrane.Element.WithInputPads.end_of_stream/3` callback.

  use Membrane.Event

  def_event()

  @impl Membrane.Event
  def sticky?(), do: true
end
