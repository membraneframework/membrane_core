defmodule Membrane.RemoteControlled.PipelineTest do
  use ExUnit.Case

  require Membrane.RemoteControlled.Pipeline

  alias Membrane.RemoteControlled.Pipeline
  alias Membrane.ParentSpec

  defmodule Filter do
    use Membrane.Filter

    def_output_pad :output, caps: :any, availability: :always

    def_input_pad :input, demand_unit: :buffers, caps: :any, availability: :always

    @impl true
    def handle_init(_opts) do
      {:ok, %{buffer_count: 0}}
    end

    @impl true
    def handle_process(_input, buf, _ctx, state) do
      state = %{state | buffer_count: state.buffer_count + 1}

      notification_actions =
        if rem(state.buffer_count, 3) == 0 do
          [{:notify, :test_notification}]
        else
          []
        end

      {{:ok, [{:buffer, {:output, buf}}] ++ notification_actions}, state}
    end

    @impl true
    def handle_demand(:output, size, _unit, _ctx, state) do
      {{:ok, demand: {:input, size}}, state}
    end
  end

  defp setup_pipeline(_context) do
    {:ok, pipeline} = Pipeline.start_link()

    children = [
      a: %Membrane.Testing.Source{output: [0xA1, 0xB2, 0xC3, 0xD4]},
      b: Filter,
      c: Membrane.Testing.Sink
    ]

    links = [ParentSpec.link(:a) |> ParentSpec.to(:b) |> ParentSpec.to(:c)]
    actions = [{:spec, %ParentSpec{children: children, links: links}}]

    Pipeline.exec_actions(pipeline, actions)
    {:ok, pipeline: pipeline}
  end

  describe "Membrane.RemoteControlled.Pipeline.subscribe/2" do
    setup :setup_pipeline

    test "testing process should receive all subscribed events", %{pipeline: pipeline} do
      Pipeline.subscribe(pipeline, {:playback_state, :prepared})
      Pipeline.subscribe(pipeline, {:playback_state, :playing})
      Pipeline.subscribe(pipeline, {:notification, :b, :test_notification})
      Pipeline.subscribe(pipeline, {:start_of_stream, :b, :input})

      Pipeline.play(pipeline)

      assert_receive {:playback_state, :prepared}
      assert_receive {:playback_state, :playing}
      assert_receive {:notification, :b, :test_notification}
      assert_receive {:start_of_stream, :b, :input}
      refute_receive {:playback_state, :terminating}
      refute_receive {:playback_state, :stopped}

      Pipeline.stop_and_terminate(pipeline, blocking?: true)
    end

    test "should allow to use wildcards in subscription pattern", %{pipeline: pipeline} do
      Pipeline.subscribe(pipeline, {:playback_state, _})
      Pipeline.subscribe(pipeline, {:end_of_stream, _, _})

      Pipeline.play(pipeline)

      assert_receive {:playback_state, :prepared}
      assert_receive {:playback_state, :playing}
      assert_receive {:end_of_stream, :b, :input}
      assert_receive {:end_of_stream, :c, :input}

      Pipeline.stop_and_terminate(pipeline, blocking?: true)

      assert_receive {:playback_state, :stopped}

      # assert_receive {:playback_state, :terminating} TODO: figure out why terminating is not delivered

      refute_receive {:notification, _, _}
      refute_receive {:start_of_stream, _, _}
    end
  end

  describe "Membrane.RemoteControlled.Pipeline" do
    setup :setup_pipeline

    test "example usage test", %{pipeline: pipeline} do
      Pipeline.subscribe(pipeline, {:playback_state, _})
      Pipeline.subscribe(pipeline, {:notification, _, _})
      Pipeline.subscribe(pipeline, {:start_of_stream, :b, :input})

      Pipeline.play(pipeline)

      Pipeline.await({:playback_state, :playing})
      Pipeline.await({:start_of_stream, :b, :input})
      Pipeline.await({:notification, :b, notification})

      assert :test_notification == notification

      Pipeline.stop_and_terminate(pipeline, blocking?: true)
    end
  end
end
