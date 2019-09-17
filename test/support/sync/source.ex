defmodule Membrane.Support.Sync.Source do
  use Membrane.Source

  def_output_pad :output, caps: :any

  def_options tick_interval: [type: :time],
              test_process: [type: :pid]

  @impl true
  def handle_init(opts), do: {:ok, opts}

  @impl true
  def handle_prepared_to_playing(ctx, %{tick_interval: interval} = state) do
    clock = ctx.pipeline_clock
    {{:ok, start_timer: {:my_timer, interval, clock}}, state}
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

  @impl true
  def handle_event(_pad, event, _ctx, state), do: {{:ok, forward: event}, state}
end
