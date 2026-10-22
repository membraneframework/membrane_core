defmodule Membrane.Support.DemandsTest.BytesSink do
  @moduledoc false
  use Membrane.Sink

  def_input_pad :input, accepted_format: _any, flow_control: :manual, demand_unit: :bytes

  @impl true
  def handle_playing(_ctx, state), do: {[notify_parent: :playing], state}

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    {[notify_parent: {:buffer, buffer}], state}
  end

  @impl true
  def handle_parent_notification({:make_demand, bytes}, _ctx, state) do
    {[demand: {:input, bytes}], state}
  end
end
