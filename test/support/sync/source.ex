defmodule Membrane.Support.Sync.Source do
  @moduledoc false
  use Membrane.Source

  def_output_pad :output, caps: :any

  def_options tick_interval: [type: :time],
              test_process: [type: :pid]

  @impl true
  def handle_playing(_ctx, %{tick_interval: interval} = state) do
    {{:ok, notify_parent: :start_timer, start_timer: {:my_timer, interval}}, state}
  end

  @impl true
  def handle_tick(:my_timer, _ctx, state) do
    send(state.test_process, :tick)
    {:ok, state}
  end

  @impl true
  def handle_demand(:output, _size, _unit, _ctx, state), do: {:ok, state}
end
