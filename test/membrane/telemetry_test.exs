defmodule Membrane.TelemetryTest do
  @moduledoc """
  Test suite for Membrane telemetry public API. It tests if telemetry events are reported
  properly for all event types and span types upon attaching to the :telemetry system.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions
  alias Membrane.Core.Telemetry
  alias Membrane.Testing
  require Logger

  @moduletag if Telemetry.legacy?(), do: :skip, else: nil

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
    @spec handle_event(atom(), any(), map(), map()) :: :ok
    def handle_event(name, value, metadata, %{dest: pid, ref: ref}) do
      pid |> send({ref, :telemetry_ack, {name, value, metadata}})
    end
  end

  setup do
    if Telemetry.legacy?() do
      [skip: true]
    else
      child_spec =
        child(:source, %Testing.Source{output: ["a", "b", "c"]})
        |> child(:filter, TestFilter)
        |> child(:sink, Testing.Sink)

      [child_spec: child_spec]
    end
  end

  @paths ~w[:filter :sink :source]
  @spans [:handle_init, :handle_setup, :handle_playing, :handle_terminate_request]
  @steps [:start, :stop]

  describe "Telemetry reports elements'" do
    setup %{child_spec: child_spec} do
      ref = make_ref()

      spans =
        for handler <- @spans,
            step <- @steps do
          [:membrane, :element, handler, step]
        end

      setup_pipeline_for_callbacks(spans, child_spec, ref)

      [ref: ref]
    end

    # Test each lifecycle step for each element type
    for element_type <- @paths,
        event <- @spans do
      test "#{element_type}/#{event}", %{ref: ref} do
        element_type = unquote(element_type)
        event = unquote(event)

        assert_receive {^ref, :telemetry_ack,
                        {[:membrane, :element, ^event, :start], results,
                         %{component_path: [_, ^element_type]}}},
                       1000

        assert results.monotonic_time < 0

        assert_receive {^ref, :telemetry_ack,
                        {[:membrane, :element, ^event, :stop], results,
                         %{component_path: [_, ^element_type]}}},
                       1000

        assert results.duration >= 0
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

      setup_pipeline_for_callbacks(spans, child_spec, ref)

      [ref: ref]
    end

    test "lifecycle", %{ref: ref} do
      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :pipeline, :handle_init, :start], results, %{}}}

      assert results.monotonic_time != 0

      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :pipeline, :handle_init, :stop], results, %{}}}

      assert results.duration >= 0

      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :pipeline, :handle_setup, :start], results, %{}}}

      assert results.monotonic_time != 0

      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :pipeline, :handle_setup, :stop], results, %{}}}

      assert results.duration >= 0
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

      pid = Testing.Pipeline.start_supervised!(spec: child_spec)

      capture_log(fn ->
        :ok = Testing.Pipeline.notify_child(pid, :filter, :crash)
      end)

      [ref: ref]
    end

    test "in element", %{ref: ref} do
      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :element, :handle_parent_notification, :start], _results,
                       %{component_path: [_, ":filter"]}}},
                     1000

      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :element, :handle_parent_notification, :exception], results,
                       %{component_path: [_, ":filter"]}}},
                     1000

      assert results.duration >= 0

      refute_received {^ref, :telemetry_ack,
                       {[:membrane, :element, :handle_parent_notification, :stop], _results, _}}
    end
  end

  describe "Telemetry properly reports following events: " do
    test "Link", %{child_spec: child_spec} do
      ref = setup_pipeline_for(:link, child_spec)

      assert_receive {^ref, :telemetry_ack, {[:membrane, :event, :link], link1, metadata}}
      assert_event_metadata(metadata)

      assert_receive {^ref, :telemetry_ack, {[:membrane, :event, :link], link2, metadata}}
      assert_event_metadata(metadata)

      assert [
               %{
                 from: ":filter",
                 pad_from: ":output",
                 pad_to: ":input",
                 parent_component_path: _,
                 to: ":sink"
               },
               %{
                 from: ":source",
                 pad_from: ":output",
                 pad_to: ":input",
                 parent_component_path: _,
                 to: ":filter"
               }
             ] = Enum.sort([link1.value, link2.value])
    end

    test "Stream Format", %{child_spec: child_spec} do
      ref = setup_pipeline_for(:stream_format, child_spec)

      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :event, :stream_format], measurement, metadata}}

      assert measurement.value.format.type == :bytestream
      assert_event_metadata(metadata)
    end

    test "Buffer", %{child_spec: child_spec} do
      ref = setup_pipeline_for(:buffer, child_spec)

      for _ <- 1..3 do
        assert_receive {^ref, :telemetry_ack,
                        {[:membrane, :event, :buffer], measurement, metadata}}

        assert measurement.value != 0
        assert_event_metadata(metadata)
      end
    end

    test "Event", %{child_spec: child_spec} do
      ref = setup_pipeline_for(:event, child_spec)

      assert_receive {^ref, :telemetry_ack, {[:membrane, :event, :event], measurement, metadata}}

      assert measurement.value.pad_ref == ":input"
      assert_event_metadata(metadata)
    end

    test "Queue Length", %{child_spec: child_spec} do
      ref = setup_pipeline_for(:queue_len, child_spec)

      assert_receive {^ref, :telemetry_ack,
                      {[:membrane, :event, :queue_len], measurement, metadata}}

      assert measurement.value
      assert_event_metadata(metadata)
    end
  end

  defp assert_event_metadata(metadata) do
    assert is_atom(metadata.event)
    assert is_list(metadata.component_path)
    assert metadata.component_metadata
  end

  defp setup_pipeline_for(event, child_spec) do
    ref = make_ref()

    :telemetry.attach(
      ref,
      [:membrane, :event, event],
      &TelemetryListener.handle_event/4,
      %{dest: self(), ref: ref}
    )

    Testing.Pipeline.start_link_supervised!(spec: child_spec)

    ref
  end

  defp setup_pipeline_for_callbacks(spans, child_spec, ref) do
    :telemetry.attach_many(ref, spans, &TelemetryListener.handle_event/4, %{
      dest: self(),
      ref: ref
    })

    pid = Testing.Pipeline.start_link_supervised!(spec: child_spec)
    assert_end_of_stream(pid, :sink)
    :ok = Testing.Pipeline.terminate(pid)
  end
end
