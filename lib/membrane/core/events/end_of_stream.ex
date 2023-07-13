defmodule Membrane.Core.Events.EndOfStream do
  @moduledoc false
  # Sent by Membrane.Element.Action.end_of_stream/
  # Invokes `c:Membrane.Element.WithInputPads.end_of_stream/3` callback.
  @derive Membrane.EventProtocol
  defstruct explicit?: false
  @type t :: %__MODULE__{explicit?: boolean()}
end
