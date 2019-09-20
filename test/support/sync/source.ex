defmodule Membrane.Support.Sync.Source do
  use Membrane.Source

  def_output_pad :output, caps: :any

  def_options tick_interval: [type: :time],
              test_process: [type: :pid]

  @impl true
  def handle_prepared_to_playing(_ctx, %{tick_interval: interval} = state) do
    {{:ok, start_timer: {:my_timer, interval}}, state}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state), do: {{:ok, stop_timer: :my_timer}, state}

  @impl true
  def handle_tick(:my_timer, _ctx, state) do
    send(state.test_process, :tick)
    {:ok, state}
  end

  @impl true
  def handle_demand(:output, _size, _, _ctx, state), do: {:ok, state}
end
