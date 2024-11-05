defmodule Membrane.Integration.ForwardingFilterTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  require Membrane.Pad, as: Pad

  alias Membrane.Buffer
  alias Membrane.ForwardingFilter
  alias Membrane.Testing

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

  test "Membrane.ForwardingFilter buffers data until output pad is linked" do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec:
          child(:source, Source)
          |> child(:filter, %ForwardingFilter{
            notify_on_event?: true,
            notify_on_stream_format?: true
          })
      )

    data = generate_data(100, [:stream_format, :buffer, :event])

    data
    |> Enum.each(fn {type, item} ->
      Testing.Pipeline.notify_child(pipeline, :source, {type, item})

      if type in [:stream_format, :event] do
        assert_pipeline_notified(pipeline, :filter, {^type, Pad.ref(:input, _id), ^item})
      end
    end)

    spec = get_child(:filter) |> child(:sink, Testing.Sink)
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
        assert_pipeline_notified(pipeline, :filter, {^type, Pad.ref(:input, _id), ^item})
      end

      case type do
        :buffer -> assert_sink_buffer(pipeline, :sink, ^item)
        :event -> assert_sink_event(pipeline, :sink, ^item)
        :stream_format -> assert_sink_stream_format(pipeline, :sink, ^item)
      end
    end)

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
end
