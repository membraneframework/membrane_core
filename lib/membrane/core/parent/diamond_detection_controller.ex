defmodule Membrane.Core.Parent.DiamondDetectionController do
  @moduledoc false

  require Membrane.Core.Message, as: Message

  alias Membrane.Core.Parent

  @spec start_diamond_detection(Parent.state()) :: :ok
  def start_diamond_detection(state) do
    state.children
    |> Enum.each(fn {_child, %{pid: child_pid}} ->
        Message.send(child_pid, :start_diamond_detection)
    end)
  end
end
