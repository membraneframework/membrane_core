defmodule Membrane.Event.Underrun do
  @moduledoc """
  Generic underrun event.

  This event means that certain element is willing to consume more buffers,
  but there are none available.

  It makes sense to use this event as an upstream event to notify previous
  elements in the pipeline that they should generate more buffers.
  """
  @derive Membrane.EventProtocol
  defstruct []
  @type t :: %__MODULE__{}
end
