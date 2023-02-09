defmodule Membrane.Integration.TimerTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.{Pipeline, Testing, Time}

  defmodule Element do
    use Membrane.Source

    @impl true
    def handle_playing(_ctx, state) do
      {[start_timer: {:timer, Time.milliseconds(100)}], state}
    end

    @impl true
    def handle_tick(:timer, _ctx, state) do
      {[notify_parent: :tick, stop_timer: :timer], state}
    end
  end

  defmodule Bin do
    use Membrane.Bin

    @impl true
    def handle_playing(_ctx, state) do
      {[start_timer: {:timer, Time.milliseconds(100)}], state}
    end

    @impl true
    def handle_tick(:timer, _ctx, state) do
      {[notify_parent: :tick, stop_timer: :timer], state}
    end
  end

  defmodule Pipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, pid) do
      spec = [child(:element, Element), child(:bin, Bin)]

      {[spec: spec], %{pid: pid}}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[start_timer: {:timer, Time.milliseconds(100)}], state}
    end

    @impl true
    def handle_tick(:timer, _ctx, state) do
      send(state.pid, :pipeline_tick)
      {[stop_timer: :timer], state}
    end
  end

  test "Stopping timer from handle_tick" do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        module: Pipeline,
        custom_args: self()
      )

    assert_pipeline_play(pipeline)
    assert_pipeline_notified(pipeline, :element, :tick)
    assert_pipeline_notified(pipeline, :bin, :tick)
    assert_receive :pipeline_tick
    Testing.Pipeline.terminate(pipeline, blocking?: true)
  end

  defmodule StopNoInterval do
    use Membrane.Source
    @impl true
    def handle_setup(_ctx, state) do
      Process.send_after(self(), :stop_timer, 0)
      {[start_timer: {:timer, :no_interval}], state}
    end

    @impl true
    def handle_info(:stop_timer, _ctx, state) do
      {[stop_timer: :timer, notify_parent: :ok], state}
    end
  end

  test "Stopping timer with `:no_interval`" do
    pipeline = Testing.Pipeline.start_link_supervised!(spec: [child(:element, StopNoInterval)])

    assert_pipeline_play(pipeline)
    assert_pipeline_notified(pipeline, :element, :ok)
    Testing.Pipeline.terminate(pipeline, blocking?: true)
  end
end
