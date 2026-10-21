defmodule Membrane.Integration.DistributedPipelineTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Support.Distributed
  alias Membrane.Testing

  defmodule PushSource do
    use Membrane.Source

    def_output_pad :output, accepted_format: _any, flow_control: :push, availability: :on_request

    @impl true
    def handle_playing(ctx, state) do
      stream_format_actions =
        Enum.map(ctx.pads, fn {pad, _data} ->
          {:stream_format, {pad, %Distributed.SomeStreamFormat{}}}
        end)

      {stream_format_actions ++ [notify_parent: :playing], state}
    end

    @impl true
    def handle_parent_notification({:buffers, buffers}, ctx, state) do
      {Enum.map(ctx.pads, fn {pad, _data} -> {:buffer, {pad, buffers}} end), state}
    end
  end

  setup do
    {peer, another_node} = start_another_node()
    on_exit(fn -> :peer.stop(peer) end)
    [first_node: node(self()), second_node: another_node]
  end

  test "if distributed pipeline works properly", context do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        module: Distributed.Pipeline,
        custom_args: context
      )

    assert_pipeline_notified(pipeline, :sink_bin, :end_of_stream)

    assert context.first_node == node(pipeline)

    assert context.first_node ==
             Testing.Pipeline.get_child_pid!(pipeline, :source)
             |> node()

    assert context.second_node ==
             Testing.Pipeline.get_child_pid!(pipeline, :sink_bin)
             |> node()

    assert context.second_node ==
             Testing.Pipeline.get_child_pid!(pipeline, [:sink_bin, :sink])
             |> node()

    Testing.Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "manual demands are supplied across nodes", context do
    payloads_count = 2000
    demands = [1, 10, 500, 1489]

    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec: [
          {child(:source, %Testing.Source{output: 1..payloads_count}), node: context.first_node},
          {get_child(:source) |> child(:sink, %Testing.Sink{autodemand: false}),
           node: context.second_node}
        ]
      )

    assert_sink_playing(pipeline, :sink)
    assert context.second_node == Testing.Pipeline.get_child_pid!(pipeline, :sink) |> node()
    refute_sink_buffer(pipeline, :sink, _buffer, 300)

    Enum.reduce(demands, 1, fn demand, next_payload ->
      Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, demand})
      assert_sink_payloads(pipeline, next_payload..(next_payload + demand - 1))
      refute_sink_buffer(pipeline, :sink, _buffer, 0)
      next_payload + demand
    end)

    assert_end_of_stream(pipeline, :sink)

    Testing.Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "toilet across nodes overflows only after the throttled decrement is flushed", context do
    toilet_capacity = 100
    distributed_throttling_factor = 150
    buffers_below_throttling_factor = distributed_throttling_factor - 1
    buffers_above_toilet_capacity = 1000

    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec: [
          {child(:source, PushSource), node: context.first_node},
          {get_child(:source)
           |> via_in(:input, toilet_capacity: toilet_capacity)
           |> child(:sink, %Testing.Sink{autodemand: false}),
           node: context.second_node, group: :sink_group, crash_group_mode: :temporary}
        ]
      )

    assert_pipeline_notified(pipeline, :source, :playing)
    assert_sink_playing(pipeline, :sink)

    send_buffers(pipeline, 1..buffers_below_throttling_factor)
    refute_pipeline_crash_group_down(pipeline, :sink_group, 300)

    Testing.Pipeline.notify_child(
      pipeline,
      :sink,
      {:make_demand, buffers_below_throttling_factor}
    )

    assert_sink_payloads(pipeline, 1..buffers_below_throttling_factor)

    first_payload_above_capacity = buffers_below_throttling_factor + 1

    send_buffers(
      pipeline,
      first_payload_above_capacity..(buffers_below_throttling_factor +
                                       buffers_above_toilet_capacity)
    )

    assert_pipeline_crash_group_down(pipeline, :sink_group)

    Testing.Pipeline.terminate(pipeline)
  end

  defp send_buffers(pipeline, payloads) do
    buffers = Enum.map(payloads, &%Membrane.Buffer{payload: &1})
    Testing.Pipeline.notify_child(pipeline, :source, {:buffers, buffers})
  end

  defp assert_sink_payloads(pipeline, payloads) do
    Enum.each(payloads, fn payload ->
      assert_sink_buffer(pipeline, :sink, buffer)
      assert buffer.payload == payload
    end)
  end

  defp start_another_node() do
    {:ok, peer, hostname} = :peer.start(%{host: ~c"127.0.0.1", name: :second})
    :rpc.block_call(hostname, :code, :add_paths, [:code.get_path()])
    {peer, hostname}
  end
end
