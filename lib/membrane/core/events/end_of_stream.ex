defmodule Membrane.Core.Events.EndOfStream do
  @moduledoc false
  # Sent by Membrane.Element.Action.end_of_stream/
  # Invokes `c:Membrane.Element.WithInputPads.end_of_stream/3` callback.
  use Membrane.Event

  def_event()
end
