defmodule Membrane.Core.Bin.DiamondDetectionController do
  @moduledoc false

  require Membrane.Core.Message, as: Message

  alias Membrane.Core.Bin.State

  # todo: trigger DD on spawning new child & linking
  @spec trigger_diamond_detection(State.t()) :: :ok
  def trigger_diamond_detection(state) do
    Message.send(state.parent, :trigger_diamond_detection)
  end
end
