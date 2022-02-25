defmodule Membrane.RemoteControlled.PipelineTest do
  use ExUnit.Case

  alias Membrane.RemoteControlled.Pipeline
  alias Membrane.ParentSpec
  alias Membrane.RemoteControlled.Pipeline.Message

  require Membrane.RemoteControlled.Pipeline

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
      Pipeline.subscribe(pipeline, %Message.PlaybackState{state: :prepared})
      Pipeline.subscribe(pipeline, %Message.PlaybackState{state: :playing})
      Pipeline.subscribe(pipeline, %Message.Notification{element: :b, data: :test_notification})
      Pipeline.subscribe(pipeline, %Message.StartOfStream{element: :b, pad: :input})

      Pipeline.play(pipeline)

      assert_receive %Message{from: ^pipeline, body: %Message.PlaybackState{state: :prepared}}
      assert_receive %Message{from: ^pipeline, body: %Message.PlaybackState{state: :playing}}
      assert_receive %Message{from: ^pipeline, body: %Message.Notification{element: :b, data: :test_notification}}
      assert_receive %Message{from: ^pipeline, body: %Message.StartOfStream{element: :b, pad: :input}}
      refute_receive  %Message{from: ^pipeline, body: %Message.PlaybackState{state: :terminating}}
      refute_receive  %Message{from: ^pipeline, body: %Message.PlaybackState{state: :stopped}}

      Pipeline.stop_and_terminate(pipeline, blocking?: true)
    end

    test "should allow to use wildcards in subscription pattern", %{pipeline: pipeline} do
      Pipeline.subscribe(pipeline, %Message.PlaybackState{state: _})
      Pipeline.subscribe(pipeline, %Message.EndOfStream{})

      Pipeline.play(pipeline)

      assert_receive %Message{from: ^pipeline, body: %Message.PlaybackState{state: :prepared}}
      assert_receive %Message{from: ^pipeline, body: %Message.PlaybackState{state: :playing}}
      assert_receive %Message{from: ^pipeline, body: %Message.EndOfStream{element: :b, pad: :input}}
      assert_receive %Message{from: ^pipeline, body: %Message.EndOfStream{element: :c, pad: :input}}

      Pipeline.stop_and_terminate(pipeline, blocking?: true)

      assert_receive %Message{from: ^pipeline, body: %Message.PlaybackState{state: :stopped}}

      # assert_receive {:playback_state, :terminating} TODO: figure out why terminating is not delivered
      refute_receive %Message{from: ^pipeline, body: %Message.Notification{}}
      refute_receive %Message{from: ^pipeline, body: %Message.StartOfStream{element: _, pad: _}}
    end
  end

  describe "Membrane.RemoteControlled.Pipeline" do
    setup :setup_pipeline

    test "should await for requested messages with await functions", %{pipeline: pipeline} do

      Pipeline.subscribe(pipeline, %Message.PlaybackState{state: _})
      Pipeline.subscribe(pipeline, %Message.StartOfStream{element: _, pad: _})
      Pipeline.subscribe(pipeline, %Message.Notification{element: _, data: _})


      Pipeline.play(pipeline)

      Pipeline.await_playback_state(pipeline, :playing)
      Pipeline.await_start_of_stream(pipeline, :c)
      Pipeline.await_notification(pipeline, :b)

      Pipeline.stop_and_terminate(pipeline, blocking?: true)
    end


    test "should await for requested messages with generic await macro", %{pipeline: pipeline} do

      Pipeline.subscribe(pipeline, %Message.PlaybackState{state: _})
      Pipeline.subscribe(pipeline, %Message.StartOfStream{element: _, pad: _})
      Pipeline.subscribe(pipeline, %Message.Notification{element: _, data: _})

      Pipeline.play(pipeline)

      Pipeline.await_generic(^pipeline, PlaybackState, state: :playing)
      Pipeline.await_generic(^pipeline, StartOfStream, element: :c)
      Pipeline.await_generic(^pipeline, Notification, element: :b)

      Pipeline.stop_and_terminate(pipeline, blocking?: true)
    end

    test "should await for requested messages with generic await macro2", %{pipeline: pipeline} do

      Pipeline.subscribe(pipeline, %Message.PlaybackState{state: _})
      Pipeline.subscribe(pipeline, %Message.StartOfStream{element: _, pad: _})
      Pipeline.subscribe(pipeline, %Message.Notification{element: _, data: _})

      Pipeline.play(pipeline)

      Pipeline.await_generic2(^pipeline, %Message.PlaybackState{state: :playing})
      Pipeline.await_generic2(^pipeline, %Message.StartOfStream{element: :c})
      Pipeline.await_generic2(^pipeline, %Message.Notification{element: :b})

      Pipeline.stop_and_terminate(pipeline, blocking?: true)
    end
  end
end
