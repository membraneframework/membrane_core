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

  test "Stopping timer from handle_tick" do
    {:ok, pipeline} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        elements: [element: Element, sink: Testing.Sink]
      })

    Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)
    assert_pipeline_notified(pipeline, :element, :tick)
    Pipeline.stop(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :stopped)
  end
end
