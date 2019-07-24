defmodule Membrane.Event.EndOfStream do
  @moduledoc """
  Generic End of Stream event.

  This event means that all buffers from the stream were processed and no further
  buffers are expected to arrive.
  `c:Membrane.Element.Base.handle_event/4` by default sends
  notification to pipeline when this event is handled.
  """
  @derive Membrane.EventProtocol
  defstruct []
  @type t :: %__MODULE__{}
end
