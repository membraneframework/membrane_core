defmodule Membrane.Integration.ActionsHandlingOrderTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  defmodule TickingPipeline do
    use Membrane.Pipeline

    @tick_time Membrane.Time.milliseconds(100)

    @impl true
    def handle_init(_ctx, test_process: test_process),
      do: {[], %{ticked?: false, test_process: test_process}}

    @impl true
    def handle_setup(_ctx, state) do
      {[setup: :incomplete, start_timer: {:one, @tick_time}], state}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[timer_interval: {:one, @tick_time}], state}
    end

    @impl true
    def handle_tick(:one, _ctx, %{ticked?: false} = state) do
      {[setup: :complete, timer_interval: {:one, :no_interval}], %{state | ticked?: true}}
    end

    @impl true
    def handle_tick(:one, _ctx, state) do
      send(state.test_process, :ticked_two_times)
      {[timer_interval: {:one, :no_interval}], state}
    end
  end

  defmodule NotifyingPipeline do
    use Membrane.Pipeline

    alias Membrane.Integration.ActionsHandlingOrderTest.NotifyingPipelineChild

    @impl true
    def handle_init(_ctx, _opts) do
      spec = child(:child, NotifyingPipelineChild)
      {[spec: spec], %{}}
    end

    @impl true
    def handle_setup(_ctx, state) do
      self() |> send(:time_to_play)
      {[setup: :incomplete], state}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[notify_child: {:child, :second_notification}], state}
    end

    @impl true
    def handle_info(:time_to_play, _ctx, state) do
      {[setup: :complete, notify_child: {:child, :first_notification}], state}
    end

    @impl true
    def handle_info({:get_notifications, test_process}, _ctx, state) do
      actions = [notify_child: {:child, :get_notifications}]
      state = Map.put(state, :test_process, test_process)

      {actions, state}
    end

    @impl true
    def handle_child_notification(notifications, :child, _ctx, state) do
      send(state.test_process, {:notifications, notifications})
      {[], state}
    end
  end

  defmodule NotifyingPipelineChild do
    use Membrane.Filter

    @impl true
    def handle_init(_ctx, _opts), do: {[], %{}}

    @impl true
    def handle_parent_notification(:get_notifications, _ctx, state) do
      {[notify_parent: state.notifications], state}
    end

    @impl true
    def handle_parent_notification(notification, _ctx, state) do
      state = Map.update(state, :notifications, [notification], &(&1 ++ [notification]))
      {[], state}
    end
  end

  defmodule TickingSink do
    use Membrane.Sink

    @tick_time Membrane.Time.milliseconds(100)

    def_input_pad :input, flow_control: :manual, demand_unit: :buffers, accepted_format: _any

    @impl true
    def handle_init(_ctx, _opts), do: {[], %{ticked?: false}}

    @impl true
    def handle_parent_notification(:start_timer, _ctx, state) do
      {[start_timer: {:timer, @tick_time}], state}
    end

    @impl true
    def handle_tick(:timer, _ctx, %{ticked?: false} = state) do
      actions = [
        demand: {:input, 1},
        timer_interval: {:timer, :no_interval}
      ]

      {actions, %{state | ticked?: true}}
    end

    @impl true
    def handle_tick(:timer, _ctx, %{ticked?: true} = state) do
      {[notify_parent: :second_tick], state}
    end

    @impl true
    def handle_buffer(:input, _buffer, _ctx, state) do
      {[timer_interval: {:timer, @tick_time}], state}
    end
  end

  test "order of handling :tick action" do
    {:ok, _supervisor, pipeline} =
      Membrane.Pipeline.start_link(TickingPipeline, test_process: self())

    assert_receive :ticked_two_times

    Membrane.Pipeline.terminate(pipeline)
  end

  test "order of handling :notify_child action" do
    {:ok, _supervisor, pipeline} = Membrane.Pipeline.start_link(NotifyingPipeline)

    # time for pipeline to play
    Process.sleep(500)

    send(pipeline, {:get_notifications, self()})

    assert_receive {:notifications, [:first_notification, :second_notification]}

    Membrane.Pipeline.terminate(pipeline)
  end

  test "order of handling :timer_interval and :demand actions" do
    spec =
      child(:source, %Testing.Source{output: [<<>>]})
      |> child(:sink, TickingSink)

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    # time for pipeline to play
    Process.sleep(500)

    Testing.Pipeline.message_child(pipeline, :sink, :start_timer)

    assert_pipeline_notified(pipeline, :sink, :second_tick)

    Testing.Pipeline.terminate(pipeline)
  end
end
