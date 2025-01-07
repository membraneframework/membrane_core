defmodule Membrane.TelemetryTest do
  @moduledoc """
  Test suite for Membrane telemetry public API. It tests if telemetry events are reported
  properly for all elements and pipelines upon attaching to the :telemetry system.
  """

  use ExUnit.Case, async: false
  alias Membrane.Testing
  import Membrane.ChildrenSpec
  require Logger

  @moduletag :telemetry
  defmodule TestFilter do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any
    def_options target: [spec: pid()]

    @impl true
    def handle_buffer(_pad, _buffer, _context, state), do: {[], state}
  end

  defmodule TelemetryListener do
    def handle_event(name, value, metadata, %{dest: pid, ref: ref}) do
      pid |> send({ref, :telemetry_ack, {name, value, metadata}})
    end
  end

  setup do
    ref = make_ref()

    links = [
      child(:source, %Testing.Source{output: [~c"a", ~c"b", ~c"c"]})
      |> child(:filter, %TestFilter{target: self()})
      |> child(:sink, Testing.Sink)
    ]

    [links: links, ref: ref]
  end

  @paths ~w[:filter :sink :source]
  @spans [:init, :setup, :playing, :terminate_request]
  @steps [:start, :stop]

  describe "Telemetry reports elements'" do
    setup %{links: links} do
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

      pid = Testing.Pipeline.start_link_supervised!(spec: links)
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
                        {[:membrane, :element, ^event, :start], value,
                         %{path: [_, ^element_type]}}},
                       1000

        assert value.system_time > 0

        assert_receive {^ref, :telemetry_ack,
                        {[:membrane, :element, ^event, :stop], value, %{path: [_, ^element_type]}}},
                       1000

        assert value.duration > 0
      end
    end
  end

  # describe "Telemetry reports pipelines'" do
  #   setup %{links: links} do
  #     ref = make_ref()

  #     spans =
  #       for event <- @spans,
  #           step <- @steps do
  #         [:membrane, :pipeline, event, step]
  #       end

  #     :telemetry.attach_many(ref, spans, &TelemetryListener.handle_event/4, %{
  #       dest: self(),
  #       ref: ref
  #     })

  #     pid = Testing.Pipeline.start_link_supervised!(spec: links)
  #     :ok = Testing.Pipeline.terminate(pid)
  #     [ref: ref]
  #   end

  #   test "lifecycle", %{ref: ref} do
  #     assert_receive {^ref, :telemetry_ack, {[:membrane, :pipeline, :init, :start], value, %{}}}
  #     assert value.system_time > 0

  #     assert_receive {^ref, :telemetry_ack, {[:membrane, :pipeline, :init, :stop], value, %{}}}
  #     assert value.duration > 0

  #     assert_receive {^ref, :telemetry_ack, {[:membrane, :pipeline, :setup, :start], value, %{}}}
  #     assert value.system_time > 0

  #     assert_receive {^ref, :telemetry_ack, {[:membrane, :pipeline, :setup, :stop], value, %{}}}
  #     assert value.duration > 0
  #   end

  #   # test "diefferent and sanitized states on start and stop", %{ref: ref} do
  #   # assert_receive {^ref, :telemetry_ack, {[:membrane, :pipeline, :init, :stop], value, _meta}}

  #   #   assert Map.has_key?(value, :children)
  #   #   refute Map.has_key?(value, :stalker)
  #   # end
  # end
end
