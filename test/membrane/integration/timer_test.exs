defmodule Membrane.Integration.TimerTest do
  use ExUnit.Case, async: true
  import Membrane.Testing.Assertions
  alias Membrane.{Pipeline, Testing, Time}

  defmodule Element do
    use Membrane.Source

    @impl true
    def handle_prepared_to_playing(_ctx, state) do
      {{:ok, start_timer: {:timer, Time.milliseconds(100)}}, state}
    end

    @impl true
    def handle_tick(:timer, _ctx, state) do
      {{:ok, notify_parent: :tick, stop_timer: :timer}, state}
    end
  end

  defmodule Bin do
    use Membrane.Bin

    @impl true
    def handle_prepared_to_playing(_ctx, state) do
      {{:ok, start_timer: {:timer, Time.milliseconds(100)}}, state}
    end

    @impl true
    def handle_tick(:timer, _ctx, state) do
      {{:ok, notify_parent: :tick, stop_timer: :timer}, state}
    end
  end

  defmodule Pipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(pid) do
      spec = %ParentSpec{
        children: [element: Element, bin: Bin]
      }

      {{:ok, spec: spec, playback: :playing}, %{pid: pid}}
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
      Testing.Pipeline.start_link(
        module: Pipeline,
        custom_args: self()
      )

    assert_pipeline_playback_changed(pipeline, _, :playing)
    assert_pipeline_notified(pipeline, :element, :tick)
    assert_pipeline_notified(pipeline, :bin, :tick)
    assert_receive :pipeline_tick
    Testing.Pipeline.execute_actions(pipeline, playback: :stopped)
    assert_pipeline_playback_changed(pipeline, _, :stopped)
    Testing.Pipeline.terminate(pipeline, blocking?: true)
  end

  defmodule StopNoInterval do
    use Membrane.Source
    @impl true
    def handle_prepared_to_playing(_ctx, state) do
      Process.send_after(self(), :stop_timer, 0)
      {{:ok, start_timer: {:timer, :no_interval}}, state}
    end

    @impl true
    def handle_info(:stop_timer, _ctx, state) do
      {{:ok, stop_timer: :timer, notify_parent: :ok}, state}
    end
  end

  test "Stopping timer with `:no_interval`" do
    {:ok, pipeline} = Testing.Pipeline.start_link(children: [element: StopNoInterval])

    assert_pipeline_playback_changed(pipeline, _, :playing)
    assert_pipeline_notified(pipeline, :element, :ok)
    Testing.Pipeline.terminate(pipeline, blocking?: true)
  end
end
