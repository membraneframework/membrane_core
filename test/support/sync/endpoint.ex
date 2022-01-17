defmodule Membrane.Support.Sync.Endpoint do
  @moduledoc false
  use Membrane.Endpoint

  def_output_pad :output, caps: :any

  def_input_pad :input, caps: :any, demand_unit: :buffers

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
  def handle_demand(:output, _size, _unit, _ctx, state), do: {:ok, state}

  def_clock()
end
