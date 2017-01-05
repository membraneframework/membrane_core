defmodule Membrane.ElementState do
  @moduledoc false
  # Structure representing state of an element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  @type t :: %Membrane.ElementState{
    internal_state: any,
    module: module,
    playback_state: :stopped | :prepared | :playing,
    source_pads: any, # FIXME
    sink_pads: any, # FIXME
    message_bus: pid,
  }

  defstruct \
    internal_state: nil,
    module: nil,
    playback_state: :stopped,
    source_pads: %{},
    sink_pads: %{},
    message_bus: nil

end
