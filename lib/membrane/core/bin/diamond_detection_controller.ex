# defmodule Membrane.Core.Bin.DiamondDetectionController do
#   @moduledoc false

#   require Membrane.Core.Message, as: Message

#   alias Membrane.Core.Bin.State

#   @spec trigger_diamond_detection(State.t()) :: :ok
#   def trigger_diamond_detection(state) do
#     Message.send(state.parent_pid, :trigger_diamond_detection)
#   end
# end
