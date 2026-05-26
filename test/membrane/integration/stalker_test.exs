defmodule Membrane.Integration.StalkerTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec

  alias Membrane.Testing

  defp run_children(pipeline) do
    Testing.Pipeline.execute_actions(pipeline,
      spec: {
        child(:source, %Testing.Source{output: [1, 2, 3]})
        |> child(:filter, Membrane.Debug.Filter)
        |> child(:sink, Testing.Sink),
        group: :children
      }
    )
  end

  defp stop_children(pipeline) do
    Testing.Pipeline.execute_actions(pipeline, remove_children: :children)
  end

  defmacrop graph_updates do
    quote do
      [
        %{
          entity: :component,
          path: [_, ":filter"],
          pid: _,
          type: :element
        },
        %{
          entity: :component,
          path: [_, ":sink"],
          pid: _,
          type: :element
        },
        %{
          entity: :component,
          path: [_, ":source"],
          pid: _,
          type: :element
        },
        %{
          entity: :link,
          from: [_, ":filter"],
          input: :input,
          output: :output,
          to: [_, ":sink"]
        },
        %{
          entity: :link,
          from: [_, ":source"],
          input: :input,
          output: :output,
          to: [_, ":filter"]
        }
      ]
    end
  end

  test "graph updates" do
    pipeline = Testing.Pipeline.start_link_supervised!()
    run_children(pipeline)
    # wait for the children to register themselves in the stalker
    Process.sleep(200)

    pipeline
    |> Membrane.Core.Pipeline.get_stalker()
    |> Membrane.Core.Stalker.subscribe([:graph])

    # should get entire graph in a single update
    assert_receive {:graph, :add, update}
    refute_receive {:graph, :add, _update}
    assert graph_updates() = Enum.sort(update)

    stop_children(pipeline)

    # should get exactly 3 updates with removal of all components and links
    updates =
      Enum.flat_map(1..3, fn _i ->
        assert_receive {:graph, :remove, update}
        update
      end)

    refute_receive {:graph, :remove, _update}

    assert graph_updates() = Enum.sort(updates)

    run_children(pipeline)

    # should get exactly 5 updates with addition of all components and links
    updates =
      Enum.flat_map(1..5, fn _i ->
        assert_receive {:graph, :add, update}
        update
      end)

    refute_receive {:graph, :add, _update}

    assert graph_updates() = Enum.sort(updates)

    Testing.Pipeline.terminate(pipeline)
  end

  test "metrics" do
    pipeline = Testing.Pipeline.start_link_supervised!()

    pipeline
    |> Membrane.Core.Pipeline.get_stalker()
    |> Membrane.Core.Stalker.subscribe([:metrics])

    run_children(pipeline)

    # we should receive some metrics
    assert_receive {:metrics, metrics, _timestamp}, 2000
    refute Enum.empty?(metrics)

    stop_children(pipeline)

    # no children == no more metrics
    refute_receive {:metrics, _metrics, _timestamp}

    Testing.Pipeline.terminate(pipeline)
  end
end
