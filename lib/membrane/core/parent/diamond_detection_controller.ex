defmodule Membrane.Core.Parent.DiamondDetectionController do
  @moduledoc false

  alias Membrane.Child
  alias Membrane.Core.Parent

  require Membrane.Core.Message, as: Message

  @spec start_diamond_detection_trigger(Child.name(), reference(), Parent.state()) :: :ok
  def start_diamond_detection_trigger(child_name, trigger_ref, state) do
    with %{component_type: :element, pid: pid} <- state.children[child_name] do
      message = %{type: :start_trigger, ref: trigger_ref}
      Message.send(pid, :diamond_detection, message)
    end

    :ok
  end
end
