defmodule Membrane.TelemetryTest do
  @moduledoc """
  Test suite for Membrane telemetry public API. It tests if telemetry events are reported
  properly for all metrics and spans upon attaching to the :telemetry system.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions
  alias Membrane.Testing
  require Logger

  defmodule TestFilter do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any

    @impl true
    def handle_buffer(_pad, buffer, _context, state), do: {[buffer: {:output, buffer}], state}

    @impl true
    def handle_parent_notification(:crash, _context, state) do
      raise "Intended Crash Test"
      {[], state}
    end
  end

  defmodule TelemetryListener do
    def handle_event(name, value, metadata, %{dest: pid, ref: ref}) do
      pid |> send({ref, :telemetry_ack, {name, value, metadata}})
    end
  end

  setup do
    child_spec =
      child(:source, %Testing.Source{output: ["a", "b", "c"]})
      |> child(:filter, TestFilter)
      |> child(:sink, Testing.Sink)

    [child_spec: child_spec]
  end

  @paths ~w[:filter :sink :source]
  @spans [:handle_init, :handle_setup, :handle_playing, :handle_terminate_request]
  @steps [:start, :stop]

  describe "Telemetry reports elements'" do
    setup %{child_spec: child_spec} do
      ref = make_ref()

      spans =
        for event <- @spans,
            step <- @steps do
          [:membrane, :element, event, step]
        end

      :telemetry.attach_many(ref, spans, &TelemetryListener.handle_event/4, %{
        dest: self(),
        ref: ref
      })

      pid = Testing.Pipeline.start_link_supervised!(spec: child_spec)
      assert_end_of_stream(pid, :sink)
      :ok = Testing.Pipeline.terminate(pid)

      [ref: ref]
    end

    # Test each lifecycle step for each element type
    for element_type <- @paths,
        event <- @spans do
      test "#{element_type}/#{event}", %{ref: ref} do
        element_type = unquote(element_type)
        event = unquote(event)

        assert_receive {^ref, :telemetry_ack,
                        {[:membrane, :element, ^event, :start], meta, %{path: [_, ^element_type]}}},
                       1000

        assert meta.system_time > 0

        assert_receive {^ref, :telemetry_ack,
                        {[:membrane, :element, ^event, :stop], meta, %{path: [_, ^element_type]}}},
                       1000

        assert meta.duration > 0
      end
    end
  end

  describe "Telemetry reports pipelines'" do
    setup %{child_spec: child_spec} do
      ref = make_ref()

      spans =
        for event <- @spans,
            step <- @steps do
          [:membrane, :pipeline, event, step]
        end

      :telemetry.attach_many(ref, spans, &TelemetryListener.handle_event/4, %{
        dest: self(),
        ref: ref
      })

      pid = Testing.Pipeline.start_link_supervised!(spec: child_spec)
      :ok = Testing.Pipeline.terminate(pid)
      [ref: ref]
    end

    test "lifecycle", %{ref: ref} do
      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :pipeline, :handle_init, :start], meta, %{}}}

      assert meta.monotonic_time != 0

      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :pipeline, :handle_init, :stop], meta, %{}}}

      assert meta.duration > 0

      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :pipeline, :handle_setup, :start], meta, %{}}}

      assert meta.monotonic_time != 0

      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :pipeline, :handle_setup, :stop], meta, %{}}}

      assert meta.duration > 0
    end
  end

  describe "Telemetry properly reports end of span when exception was encountered" do
    setup %{child_spec: child_spec} do
      ref = make_ref()

      spans =
        [
          [:membrane, :element, :handle_parent_notification, :start],
          [:membrane, :element, :handle_parent_notification, :stop],
          [:membrane, :element, :handle_parent_notification, :exception]
        ]

      :telemetry.attach_many(ref, spans, &TelemetryListener.handle_event/4, %{
        dest: self(),
        ref: ref
      })

      pid = Testing.Pipeline.start_link_supervised!(spec: child_spec)
      Process.flag(:trap_exit, true)

      capture_log(fn ->
        :ok = Testing.Pipeline.notify_child(pid, :filter, :crash)
      end)

      [ref: ref]
    end

    test "in element", %{ref: ref} do
      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :element, :handle_parent_notification, :start], _meta,
                       %{path: [_, ":filter"]}}},
                     1000

      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :element, :handle_parent_notification, :exception], meta,
                       %{path: [_, ":filter"]}}},
                     1000

      assert meta.duration > 0

      refute_received {^ref, :telemetry_ack,
                       {[:membrane, :element, :handle_parent_notification, :stop], _meta, _}}
    end
  end

  describe "Telemetry properly reports following metrics: " do
    test "Link", %{child_spec: child_spec} do
      ref = setup_pipeline_for(:link, child_spec)

      assert_receive {^ref, :telemetry_ack, {[:membrane, :metric, :link], _value, _metadata}}
    end

    # test "Store", %{child_spec: child_spec} do
    #   ref = setup_pipeline_for(:store, child_spec)

    #   assert_receive {^ref, :telemetry_ack, {[:membrane, :metric, :store], _value, _metadata}},
    #                  1000
    # end

    # test "Take", %{child_spec: child_spec} do
    #   ref = setup_pipeline_for(:take, child_spec)

    #   assert_receive {^ref, :telemetry_ack, {[:membrane, :metric, :take], _value, _metadata}}
    # end

    test "Stream Format", %{child_spec: child_spec} do
      ref = setup_pipeline_for(:stream_format, child_spec)

      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :metric, :stream_format], _value, _metadata}}
    end

    test "Buffer", %{child_spec: child_spec} do
      ref = setup_pipeline_for(:buffer, child_spec)

      assert_receive {^ref, :telemetry_ack, {[:membrane, :metric, :buffer], _value, _metadata}}
    end

    test "Bitrate", %{child_spec: child_spec} do
      ref = setup_pipeline_for(:bitrate, child_spec)

      assert_receive {^ref, :telemetry_ack, {[:membrane, :metric, :bitrate], _value, _metadata}}
    end

    test "Event", %{child_spec: child_spec} do
      ref = setup_pipeline_for(:event, child_spec)

      assert_receive {^ref, :telemetry_ack, {[:membrane, :metric, :event], _value, _metadata}}
    end

    test "Queue Length", %{child_spec: child_spec} do
      ref = setup_pipeline_for(:queue_len, child_spec)

      assert_receive {^ref, :telemetry_ack, {[:membrane, :metric, :queue_len], _value, _metadata}}
    end
  end

  defp setup_pipeline_for(metric, child_spec) do
    ref = make_ref()

    :telemetry.attach(
      ref,
      [:membrane, :metric, metric],
      &TelemetryListener.handle_event/4,
      %{dest: self(), ref: ref}
    )

    Testing.Pipeline.start_link_supervised!(spec: child_spec)

    ref
  end
end
