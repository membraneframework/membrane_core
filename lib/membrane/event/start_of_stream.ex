defmodule Membrane.Event.StartOfStream do
  @moduledoc """
  Generic Start of Stream event.

  This event means that first buffers have been sent and will arrive to the
  pad right away after handling the event.
  """
  defstruct []
  @type t :: %__MODULE__{}
end

defimpl Membrane.EventProtocol, for: Membrane.Event.StartOfStream do
  use Membrane.EventProtocol.DefaultImpl
  @impl true
  def sticky?(_), do: true
end
