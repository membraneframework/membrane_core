defmodule Membrane.Integration.ConnectorTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Connector
  alias Membrane.Testing

  require Membrane.Pad, as: Pad

  defmodule Format do
    defstruct [:field]
  end

  defmodule Source do
    use Membrane.Source
    def_output_pad :output, accepted_format: _any, flow_control: :push

    @impl true
    def handle_parent_notification({action, item}, _ctx, state),
      do: {[{action, {:output, item}}], state}
  end

  test "Membrane.Connector buffers data until output pad is linked" do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec:
          child(:source, Source)
          |> child(:connector, %Connector{
            notify_on_event?: true,
            notify_on_stream_format?: true
          })
      )

    assert_child_playing(pipeline, :source)

    data = generate_data(100, [:stream_format, :buffer, :event])

    data
    |> Enum.each(fn {type, item} ->
      Testing.Pipeline.notify_child(pipeline, :source, {type, item})

      if type in [:stream_format, :event] do
        assert_pipeline_notified(pipeline, :connector, {^type, Pad.ref(:input, _id), ^item})
      end
    end)

    spec = get_child(:connector) |> child(:sink, Testing.Sink)
    Testing.Pipeline.execute_actions(pipeline, spec: spec)

    data
    |> Enum.each(fn
      {:buffer, item} -> assert_sink_buffer(pipeline, :sink, ^item)
      {:event, item} -> assert_sink_event(pipeline, :sink, ^item)
      {:stream_format, item} -> assert_sink_stream_format(pipeline, :sink, ^item)
    end)

    data = generate_data(100, [:stream_format, :buffer, :event], 200)

    data
    |> Enum.each(fn {type, item} ->
      Testing.Pipeline.notify_child(pipeline, :source, {type, item})

      if type in [:stream_format, :event] do
        assert_pipeline_notified(pipeline, :connector, {^type, Pad.ref(:input, _id), ^item})
      end

      case type do
        :buffer -> assert_sink_buffer(pipeline, :sink, ^item)
        :event -> assert_sink_event(pipeline, :sink, ^item)
        :stream_format -> assert_sink_stream_format(pipeline, :sink, ^item)
      end
    end)

    Testing.Pipeline.terminate(pipeline)
  end

  test "Membrane.Connector pauses input demand if output pad is not linked" do
    atomics_ref = :atomics.new(1, [])
    :atomics.put(atomics_ref, 1, 0)

    generator = fn _initial_state, _demand_size ->
      :atomics.add(atomics_ref, 1, 1)
      buffer = %Membrane.Buffer{payload: <<>>}
      {[buffer: {:output, buffer}, redemand: :output], nil}
    end

    auto_demand_size = 20

    spec =
      child(:source, %Testing.Source{output: {nil, generator}})
      |> via_in(:input, auto_demand_size: auto_demand_size)
      |> child(:connector, Connector)

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    Process.sleep(500)

    assert :atomics.get(atomics_ref, 1) == auto_demand_size

    spec = get_child(:connector) |> child(:sink, Testing.Sink)
    Testing.Pipeline.execute_actions(pipeline, spec: spec)

    Process.sleep(500)

    assert :atomics.get(atomics_ref, 1) > auto_demand_size + 100

    Testing.Pipeline.terminate(pipeline)
  end

  defp generate_data(number, types, pts_offset \\ 0) do
    data =
      1..(number - 1)
      |> Enum.map(fn i ->
        case Enum.random(types) do
          :stream_format -> {:stream_format, %Format{field: i}}
          :event -> {:event, %Testing.Event{}}
          :buffer -> {:buffer, %Buffer{pts: i + pts_offset, payload: <<>>}}
        end
      end)

    [stream_format: %Format{field: 0}] ++ data
  end

  test "Membrane.Connector doesn't raise after removing its pad" do
    crash_group_spec = {
      for i <- 2..5 do
        child({:connector, i}, Membrane.Connector)
      end,
      group: :my_group, crash_group_mode: :temporary
    }

    children_beyond_crash_group = [
      child(:source, Testing.Source)
      |> child({:connector, 1}, Membrane.Connector),
      child({:connector, 6}, Membrane.Connector)
      |> child(:sink, Testing.Sink)
    ]

    connector_links =
      for i <- 1..5 do
        get_child({:connector, i})
        |> get_child({:connector, i + 1})
      end

    spec = [crash_group_spec, children_beyond_crash_group, connector_links]
    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    Process.sleep(200)

    {:ok, connector_pid} = Testing.Pipeline.get_child_pid(pipeline, {:connector, 3})
    Process.exit(connector_pid, :kill)

    Process.sleep(200)

    assert Process.alive?(connector_pid) == false
    assert Process.alive?(pipeline)

    Testing.Pipeline.terminate(pipeline)
  end
end
