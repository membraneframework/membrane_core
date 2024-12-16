defmodule Membrane.TelemetryTest do
  @moduledoc """
  Test suite for Membrane telemetry public API. It tests if telemetry events are reported
  properly for all elements and pipelines upon attaching to the :telemetry system.
  """

  use ExUnit.Case, async: false
  alias Membrane.Testing
  import Membrane.ChildrenSpec
  require Logger

  defmodule TestFilter do
    use Membrane.Filter

    def_input_pad :input, flow_control: :manual, accepted_format: _any, demand_unit: :buffers
    def_output_pad :output, flow_control: :manual, accepted_format: _any
    def_options target: [spec: pid()]

    @impl true
    def handle_demand(_pad, size, _unit, _context, state) do
      {[demand: {:input, size}], state}
    end

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
  @events [:init, :setup, :playing, :terminate]
  @steps [:start, :stop]

  describe "Telemetry reports elements" do
    @tag :telemetry

    setup %{links: links} do
      ref = make_ref()

      events =
        for event <- @events,
            step <- @steps do
          [:membrane, :element, event, step]
        end

      :telemetry.attach_many(ref, events, &TelemetryListener.handle_event/4, %{
        dest: self(),
        ref: ref
      })

      pid = Testing.Pipeline.start_link_supervised!(spec: links)
      :ok = Testing.Pipeline.terminate(pid)
      [ref: ref]
    end

    # Test each lifecycle step for each element type
    for element_type <- @paths,
        event <- @events do
      test "#{element_type}/#{event}", %{ref: ref} do
        element_type = unquote(element_type)
        event = unquote(event)

        assert_receive {^ref, :telemetry_ack,
                        {[:membrane, :element, ^event, :start], meta, %{path: [_, ^element_type]}}}

        assert meta.system_time > 0

        assert_receive {^ref, :telemetry_ack,
                        {[:membrane, :element, ^event, :stop], meta, %{path: [_, ^element_type]}}}

        assert meta.duration > 0
      end
    end
  end

  describe "Pipelines" do
    setup %{links: links} do
      ref = make_ref()

      events =
        for event <- @events,
            step <- @steps do
          [:membrane, :pipeline, event, step]
        end

      :telemetry.attach_many(ref, events, &TelemetryListener.handle_event/4, %{
        dest: self(),
        ref: ref
      })

      pid = Testing.Pipeline.start_link_supervised!(spec: links)
      :ok = Testing.Pipeline.terminate(pid)
      [ref: ref]
    end

    test "Pipeline lifecycle", %{ref: ref} do
      assert_receive {^ref, :telemetry_ack, {[:membrane, :pipeline, :init, :start], meta, %{}}}
      assert meta.system_time > 0

      assert_receive {^ref, :telemetry_ack, {[:membrane, :pipeline, :init, :stop], meta, %{}}}
      assert meta.duration > 0

      assert_receive {^ref, :telemetry_ack, {[:membrane, :pipeline, :setup, :start], meta, %{}}}
      assert meta.system_time > 0

      assert_receive {^ref, :telemetry_ack, {[:membrane, :pipeline, :setup, :stop], meta, %{}}}
      assert meta.duration > 0
    end
  end
end
