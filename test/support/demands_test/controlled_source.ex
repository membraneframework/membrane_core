defmodule Membrane.Support.DemandsTest.ControlledSource do
  @moduledoc false
  use Membrane.Source

  def_output_pad :output, accepted_format: _any, flow_control: :manual

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, %Membrane.RemoteStream{}}, notify_parent: :playing], state}
  end

  @impl true
  def handle_parent_notification(actions, _ctx, state), do: {actions, state}

  @impl true
  def handle_demand(:output, _size, :buffers, _ctx, state), do: {[], state}
end
