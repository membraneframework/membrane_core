defmodule Membrane.Core.Events.EndOfStream do
  @moduledoc false
  # Sent by Membrane.Element.Action.end_of_stream/
  # Invokes `c:Membrane.Element.WithInputPads.end_of_stream/3` callback.
  @derive Membrane.EventProtocol
  defstruct []
  @type t :: %__MODULE__{}
end
