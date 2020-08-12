defmodule Membrane.Integration.TimerTest do
  use ExUnit.Case, async: true
  import Membrane.Testing.Assertions
  alias Membrane.{Pipeline, Testing, Time}

  defmodule Element do
    use Membrane.Source

    def_output_pad :output, mode: :push, caps: :any

    @impl true
    def handle_prepared_to_playing(_ctx, state) do
      {{:ok, start_timer: {:timer, Time.milliseconds(100)}}, state}
    end

    @impl true
    def handle_tick(:timer, _ctx, state) do
      {{:ok, notify: :tick, stop_timer: :timer}, state}
    end
  end

  defmodule Bin do
    use Membrane.Bin

    def_input_pad :input, mode: :push, caps: :any

    @impl true
    def handle_prepared_to_playing(_ctx, state) do
      {{:ok, start_timer: {:timer, Time.milliseconds(100)}}, state}
    end

    @impl true
    def handle_tick(:timer, _ctx, state) do
      {{:ok, notify: :tick, stop_timer: :timer}, state}
    end
  end

  defmodule Pipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(pid) do
      spec = %ParentSpec{
        children: [element: Element, bin: Bin],
        links: [link(:element) |> to(:bin)]
      }

      {{:ok, spec: spec}, %{pid: pid}}
    end

    @impl true
    def handle_prepared_to_playing(_ctx, state) do
      {{:ok, start_timer: {:timer, Time.milliseconds(100)}}, state}
    end

    @impl true
    def handle_tick(:timer, _ctx, state) do
      send(state.pid, :pipeline_tick)
      {{:ok, stop_timer: :timer}, state}
    end
  end

  test "Stopping timer from handle_tick" do
    {:ok, pipeline} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        module: Pipeline,
        custom_args: self()
      })

    Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)
    assert_pipeline_notified(pipeline, :element, :tick)
    assert_pipeline_notified(pipeline, :bin, :tick)
    assert_receive :pipeline_tick
    Pipeline.stop(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :stopped)
  end
end
