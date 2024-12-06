defmodule Membrane.TelemetryTest do
  use ExUnit.Case, async: false
  import Membrane.ChildrenSpec

  require Logger
  alias Membrane.Testing

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

  describe "Telemetry reports" do
    @tag :telemetry

    @paths ~w[:filter :sink :source]
    @events [:init, :setup]
    @steps [:start, :stop]

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

      Testing.Pipeline.start_link_supervised!(spec: links)
      [ref: ref]
    end

    # Test each lifecycle step for each element type
    for path <- @paths,
        event <- @events do
      test "#{path}/#{event}", %{ref: ref} do
        path = unquote(path)
        event = unquote(event)

        assert_receive {^ref, :telemetry_ack,
                        {[:membrane, :element, ^event, :start], meta, %{path: [_, ^path]}}}

        assert meta.system_time > 0

        assert_receive {^ref, :telemetry_ack,
                        {[:membrane, :element, ^event, :stop], meta, %{path: [_, ^path]}}}

        assert meta.duration > 0
      end
    end
  end
end
