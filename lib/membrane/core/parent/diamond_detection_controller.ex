defmodule Membrane.Core.Parent.DiamondDetectionController do
  @moduledoc false

  require Membrane.Core.Message, as: Message

  alias Membrane.Core.Parent

  @spec start_diamond_detection(Parent.state()) :: :ok
  def start_diamond_detection(state) do
    children_with_input_pads =
      state.links
      |> MapSet.new(& &1.to.child)

    state.children
    |> Enum.each(fn {child, child_data} ->
      if child_data.component_type == :bin or not MapSet.member?(children_with_input_pads, child) do
        Message.send(child_data.pid, :start_diamond_detection)
      end
    end)
  end
end
