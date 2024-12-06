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

  describe "Telemetry attaching" do
    @tag :telemetry

    test "handles init events", %{ref: ref, links: links} do
      :ok =
        [
          [:membrane, :element, :init],
          [:membrane, :pipeline, :init]
        ]
        |> attach_to_events(ref)

      Testing.Pipeline.start_link_supervised!(spec: links)

      assert_receive({^ref, :telemetry_ack, {[:membrane, :pipeline, :init], _, _}}, 1000)
      assert_receive({^ref, :telemetry_ack, {[:membrane, :element, :init], e1, _}}, 1000)
      assert_receive({^ref, :telemetry_ack, {[:membrane, :element, :init], e2, _}}, 1000)
      assert_receive({^ref, :telemetry_ack, {[:membrane, :element, :init], e3, _}}, 1000)

      elements =
        [e1, e2, e3]
        |> Enum.map(&extract_type/1)
        |> Enum.sort()

      assert ^elements = ["filter", "sink", "source"]
    end

    test "handles terminate events", %{ref: ref, links: links} do
      :ok =
        [
          [:membrane, :element, :terminate],
          [:membrane, :pipeline, :terminate]
        ]
        |> attach_to_events(ref)

      pid = Testing.Pipeline.start_link_supervised!(spec: links)
      :ok = Testing.Pipeline.terminate(pid)

      assert_receive({^ref, :telemetry_ack, {[:membrane, :pipeline, :terminate], _, _}}, 1000)
      assert_receive({^ref, :telemetry_ack, {[:membrane, :element, :terminate], e1, _}}, 1000)
      assert_receive({^ref, :telemetry_ack, {[:membrane, :element, :terminate], e2, _}}, 1000)
      assert_receive({^ref, :telemetry_ack, {[:membrane, :element, :terminate], e3, _}}, 1000)

      elements =
        [e1, e2, e3]
        |> Enum.map(&extract_type/1)
        |> Enum.sort()

      assert ^elements = ["filter", "sink", "source"]
    end
  end

  describe "Telemetry reports" do
    @tag :telemetry

    @paths ~w[:filter :sink :source]
    @steps [:init, :setup]

    setup %{links: links} do
      ref = make_ref()

      for step <- @steps do
        [:membrane, :element, :span, step]
      end
      |> attach_to_events(ref)

      Testing.Pipeline.start_link_supervised!(spec: links)
      [ref: ref]
    end

    for path <- @paths, step <- @steps do
      test "#{path}/#{step}", %{ref: ref} do
        path = unquote(path)
        step = unquote(step)

        assert_receive(
          {^ref, :telemetry_ack,
           {[:membrane, :element, :span, ^step], %{path: [_, ^path], time: time}, _}}
        )

        assert time > 0
      end
    end
  end

  defp attach_to_events(events, ref) do
    :ok =
      :telemetry.attach_many(ref, events, &TelemetryListener.handle_event/4, %{
        dest: self(),
        ref: ref
      })
  end

  defp extract_type(%{path: pid_type}) do
    String.split(pid_type, ":") |> List.last()
  end
end
