defmodule Membrane.Core.Pipeline.DiamondDetectionController do
  @moduledoc false

  require Membrane.Core.Message, as: Message

  alias Membrane.Core.Parent
  alias Membrane.Core.Pipeline.State

  @spec trigger_diamond_detection(State.t()) :: State.t()
  def trigger_diamond_detection(%State{} = state) when state.diamond_detection_triggered? do
    state
  end

  def trigger_diamond_detection(%State{} = state) do
    message = Message.new(:start_diamond_detection)
    send_after_timeout = Membrane.Time.second() |> Membrane.Time.as_milliseconds(:round)
    self() |> Process.send_after(message, send_after_timeout)

    %{state | diamond_detection_triggered?: true}
  end

  @spec start_diamond_detection(State.t()) :: State.t()
  def start_diamond_detection(%State{} = state) do
    :ok = Parent.DiamondDetectionController.start_diamond_detection(state)
    %{state | diamond_detection_triggered?: false}
  end
end
