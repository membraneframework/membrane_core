defmodule Membrane.Support.Sync.Source do
  @moduledoc false
  use Membrane.Source

  def_output_pad :output, accepted_format: _any

  def_options tick_interval: [spec: Membrane.Time.t()],
              test_process: [spec: pid()]

  @impl true
  def handle_playing(_ctx, %{tick_interval: interval} = state) do
    {[notify_parent: :start_timer, start_timer: {:my_timer, interval}], state}
  end

  @impl true
  def handle_tick(:my_timer, _ctx, state) do
    send(state.test_process, :tick)
    {[], state}
  end

  @impl true
  def handle_demand(:output, _size, _unit, _ctx, state), do: {[], state}
end
