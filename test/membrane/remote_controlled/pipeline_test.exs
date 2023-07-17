defmodule Membrane.RCPipelineTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec

  alias Membrane.RCMessage
  alias Membrane.RCPipeline

  require Membrane.RCPipeline

  defmodule Filter do
    use Membrane.Filter
    alias Membrane.Buffer

    def_output_pad :output, flow_control: :manual, accepted_format: _any, availability: :always

    def_input_pad :input,
      flow_control: :manual,
      demand_unit: :buffers,
      accepted_format: _any,
      availability: :always

    @impl true
    def handle_init(_ctx, _opts) do
      {[], %{buffer_count: 0}}
    end

    @impl true
    def handle_buffer(_input, buf, _ctx, state) do
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
    {:ok, _supervisor, pipeline} = start_supervised({RCPipeline, controller_pid: self()})
    Process.link(pipeline)

    {:ok, pipeline: pipeline}
  end

  describe "Membrane.RCPipeline.subscribe/2" do
    setup :setup_pipeline

    test "testing process should receive all subscribed events", %{pipeline: pipeline} do
      # SETUP
      RCPipeline.subscribe(pipeline, %RCMessage.Notification{
        element: :b,
        data: %Membrane.Buffer{}
      })

      RCPipeline.subscribe(pipeline, %RCMessage.StartOfStream{element: :b, pad: :input})

      # RUN
      RCPipeline.exec_actions(pipeline, spec: @pipeline_spec)

      # TEST
      assert_receive %RCMessage.Notification{
        from: ^pipeline,
        element: :b,
        data: %Membrane.Buffer{payload: "test"}
      }

      assert_receive %RCMessage.StartOfStream{from: ^pipeline, element: :b, pad: :input}

      refute_receive %RCMessage.Terminated{from: ^pipeline}
    end

    test "should allow to use wildcards in subscription pattern", %{pipeline: pipeline} do
      # SETUP
      RCPipeline.subscribe(pipeline, %RCMessage.EndOfStream{})

      # RUN
      RCPipeline.exec_actions(pipeline, spec: @pipeline_spec)

      # TEST
      assert_receive %RCMessage.EndOfStream{from: ^pipeline, element: :b, pad: :input}

      assert_receive %RCMessage.EndOfStream{from: ^pipeline, element: :c, pad: :input}

      # STOP
      RCPipeline.terminate(pipeline)

      # TEST
      refute_receive %RCMessage.Terminated{from: ^pipeline}
      refute_receive %RCMessage.Notification{from: ^pipeline}
      refute_receive %RCMessage.StartOfStream{from: ^pipeline, element: _, pad: _}
    end
  end

  describe "Membrane.RCPipeline await_* functions" do
    setup :setup_pipeline

    test "should await for requested messages", %{pipeline: pipeline} do
      # SETUP
      RCPipeline.subscribe(pipeline, %RCMessage.StartOfStream{element: _, pad: _})
      RCPipeline.subscribe(pipeline, %RCMessage.Notification{element: _, data: _})
      RCPipeline.subscribe(pipeline, %RCMessage.Terminated{})

      # RUN
      RCPipeline.exec_actions(pipeline, spec: @pipeline_spec)

      # TEST
      RCPipeline.await_start_of_stream(pipeline, :c, :input)
      RCPipeline.await_notification(pipeline, :b)
    end

    test "should await for requested messages with parts of message body not being specified", %{
      pipeline: pipeline
    } do
      # SETUP
      RCPipeline.subscribe(pipeline, %RCMessage.StartOfStream{element: _, pad: _})
      RCPipeline.subscribe(pipeline, %RCMessage.Notification{element: _, data: _})

      # RUN
      RCPipeline.exec_actions(pipeline, spec: @pipeline_spec)

      # TEST
      RCPipeline.await_start_of_stream(pipeline, :c)
      msg = RCPipeline.await_notification(pipeline, :b)

      assert msg == %RCMessage.Notification{
               from: pipeline,
               element: :b,
               data: %Membrane.Buffer{payload: "test"}
             }
    end

    test "should await for requested messages with pinned variables as message body parts", %{
      pipeline: pipeline
    } do
      # SETUP
      RCPipeline.subscribe(pipeline, %RCMessage.StartOfStream{element: _, pad: _})
      RCPipeline.subscribe(pipeline, %RCMessage.Notification{element: _, data: _})
      element = :c

      # START
      RCPipeline.exec_actions(pipeline, spec: @pipeline_spec)

      # TEST
      RCPipeline.await_start_of_stream(pipeline, element, :input)
    end
  end
end
