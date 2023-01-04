defmodule Membrane.RemoteControlled.PipelineTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec

  alias Membrane.RemoteControlled.Message
  alias Membrane.RemoteControlled.Pipeline

  require Membrane.RemoteControlled.Pipeline

  defmodule Filter do
    use Membrane.Filter
    alias Membrane.Buffer

    def_output_pad :output, accepted_format: _any, availability: :always
    def_input_pad :input, demand_unit: :buffers, accepted_format: _any, availability: :always

    @impl true
    def handle_init(_ctx, _opts) do
      {[], %{buffer_count: 0}}
    end

    @impl true
    def handle_process(_input, buf, _ctx, state) do
      state = %{state | buffer_count: state.buffer_count + 1}

      notification_actions =
        if rem(state.buffer_count, 3) == 0 do
          [{:notify_parent, %Buffer{payload: "test"}}]
        else
          []
        end

      {[{:buffer, {:output, buf}}] ++ notification_actions, state}
    end

    @impl true
    def handle_demand(:output, size, _unit, _ctx, state) do
      {[demand: {:input, size}], state}
    end
  end

  @pipeline_spec child(:a, %Membrane.Testing.Source{output: [0xA1, 0xB2, 0xC3, 0xD4]})
                 |> child(:b, Filter)
                 |> child(:c, Membrane.Testing.Sink)

  defp setup_pipeline(_context) do
    {:ok, _supervisor, pipeline} = start_supervised({Pipeline, controller_pid: self()})
    Process.link(pipeline)

    {:ok, pipeline: pipeline}
  end

  describe "Membrane.RemoteControlled.Pipeline.subscribe/2" do
    setup :setup_pipeline

    test "testing process should receive all subscribed events", %{pipeline: pipeline} do
      # SETUP
      Pipeline.subscribe(pipeline, %Message.Notification{element: :b, data: %Membrane.Buffer{}})
      Pipeline.subscribe(pipeline, %Message.StartOfStream{element: :b, pad: :input})

      # RUN
      Pipeline.exec_actions(pipeline, spec: @pipeline_spec)

      # TEST
      assert_receive %Message.Notification{
        from: ^pipeline,
        element: :b,
        data: %Membrane.Buffer{payload: "test"}
      }

      assert_receive %Message.StartOfStream{from: ^pipeline, element: :b, pad: :input}

      refute_receive %Message.Terminated{from: ^pipeline}
    end

    test "should allow to use wildcards in subscription pattern", %{pipeline: pipeline} do
      # SETUP
      Pipeline.subscribe(pipeline, %Message.EndOfStream{})

      # RUN
      Pipeline.exec_actions(pipeline, spec: @pipeline_spec)

      # TEST
      assert_receive %Message.EndOfStream{from: ^pipeline, element: :b, pad: :input}

      assert_receive %Message.EndOfStream{from: ^pipeline, element: :c, pad: :input}

      # STOP
      Pipeline.terminate(pipeline, blocking?: true)

      # TEST
      refute_receive %Message.Terminated{from: ^pipeline}
      refute_receive %Message.Notification{from: ^pipeline}
      refute_receive %Message.StartOfStream{from: ^pipeline, element: _, pad: _}
    end
  end

  describe "Membrane.RemoteControlled.Pipeline await_* functions" do
    setup :setup_pipeline

    test "should await for requested messages", %{pipeline: pipeline} do
      # SETUP
      Pipeline.subscribe(pipeline, %Message.StartOfStream{element: _, pad: _})
      Pipeline.subscribe(pipeline, %Message.Notification{element: _, data: _})
      Pipeline.subscribe(pipeline, %Message.Terminated{})

      # RUN
      Pipeline.exec_actions(pipeline, spec: @pipeline_spec)

      # TEST
      Pipeline.await_start_of_stream(pipeline, :c, :input)
      Pipeline.await_notification(pipeline, :b)
    end

    test "should await for requested messages with parts of message body not being specified", %{
      pipeline: pipeline
    } do
      # SETUP
      Pipeline.subscribe(pipeline, %Message.StartOfStream{element: _, pad: _})
      Pipeline.subscribe(pipeline, %Message.Notification{element: _, data: _})

      # RUN
      Pipeline.exec_actions(pipeline, spec: @pipeline_spec)

      # TEST
      Pipeline.await_start_of_stream(pipeline, :c)
      msg = Pipeline.await_notification(pipeline, :b)

      assert msg == %Message.Notification{
               from: pipeline,
               element: :b,
               data: %Membrane.Buffer{payload: "test"}
             }
    end

    test "should await for requested messages with pinned variables as message body parts", %{
      pipeline: pipeline
    } do
      # SETUP
      Pipeline.subscribe(pipeline, %Message.StartOfStream{element: _, pad: _})
      Pipeline.subscribe(pipeline, %Message.Notification{element: _, data: _})
      element = :c

      # START
      Pipeline.exec_actions(pipeline, spec: @pipeline_spec)

      # TEST
      Pipeline.await_start_of_stream(pipeline, element, :input)
    end
  end
end
