defmodule Membrane.Core.Events.StartOfStream do
  @moduledoc false
  # Generated before processing the first buffer.
  # Invokes `c:Membrane.Element.WithInputPads.end_of_stream/3` callback.
  defstruct []
  @type t :: %__MODULE__{}
end

defimpl Membrane.EventProtocol, for: Membrane.Core.Events.StartOfStream do
  use Membrane.EventProtocol.DefaultImpl
  @impl true
  def sticky?(_event), do: true
end
