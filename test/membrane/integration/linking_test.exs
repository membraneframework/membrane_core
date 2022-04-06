defmodule Membrane.Integration.LinkingTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions
  import Membrane.ParentSpec

  alias Membrane.{Testing, Buffer}

  defmodule Bin do
    use Membrane.Bin

    def_options child: [
                  spec: struct() | module()
                ]

    def_output_pad :output, demand_unit: :buffers, caps: :any, availability: :on_request

    @impl true
    def handle_init(opts) do
      children = [
        source: opts.child
      ]

      spec = %ParentSpec{
        children: children
      }

      {{:ok, spec: spec}, %{}}
    end

    @impl true
    def handle_pad_added(pad, _ctx, _state) do
      links = [
        link(:source) |> to_bin_output(pad)
      ]

      spec = %ParentSpec{
        links: links
      }

      {{:ok, spec: spec}, %{}}
    end

    @impl true
    def handle_pad_removed(_pad, _ctx, _state) do
      {{:ok, notify: :handle_pad_removed}, %{}}
    end
  end

  defmodule Pipeline do
    @moduledoc false
    use Membrane.Pipeline

    @impl true
    def handle_init(opts) do
      {:ok, %{testing_pid: opts.testing_pid}}
    end

    @impl true
    def handle_other({:start_spec, %{spec: spec}}, _ctx, state) do
      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_other(
          {:start_spec_and_kill, %{spec: spec, children_to_kill: children_to_kill}},
          ctx,
          state
        ) do
      Enum.each(children_to_kill, &Process.exit(ctx.children[&1].pid, :kill))
      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_other({:remove_child, child}, _ctx, state) do
      {{:ok, remove_child: child}, state}
    end

    @impl true
    def handle_spec_started(_children, _ctx, state) do
      send(state.testing_pid, :spec_started)
      {:ok, state}
    end
  end

  setup do
    {:ok, pipeline} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        module: Pipeline,
        custom_args: %{testing_pid: self()}
      })

    on_exit(fn ->
      Membrane.Pipeline.stop_and_terminate(pipeline, blocking?: true)
    end)

    %{pipeline: pipeline}
  end

  describe "when element is connected to a bin" do
    test "and element is removed normally, handle_pad_removed should be called", %{
      pipeline: pipeline
    } do
      spec = %Membrane.ParentSpec{
        children: [
          bin: %Bin{child: %Testing.Source{output: ['a', 'b', 'c']}},
          sink: Testing.Sink
        ],
        links: [
          link(:bin) |> to(:sink)
        ]
      }

      send(pipeline, {:start_spec, %{spec: spec}})
      assert_receive(:spec_started)
      Testing.Pipeline.play(pipeline)
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: 'a'})
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: 'b'})
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: 'c'})
      send(pipeline, {:remove_child, :sink})
      assert_pipeline_notified(pipeline, :bin, :handle_pad_removed)
    end

    test "and element crashes, bin forwards the unlink message to child", %{pipeline: pipeline} do
      bin_spec = %Membrane.ParentSpec{
        children: [
          bin: %Bin{child: %Testing.Source{output: ['a', 'b', 'c']}}
        ],
        crash_group: {:group_1, :temporary}
      }

      sink_spec = %Membrane.ParentSpec{
        children: [
          sink: Testing.Sink
        ],
        crash_group: {:group_2, :temporary}
      }

      links_spec = %Membrane.ParentSpec{
        links: [
          link(:bin) |> to(:sink)
        ]
      }

      send(pipeline, {:start_spec, %{spec: bin_spec}})
      assert_receive(:spec_started)
      send(pipeline, {:start_spec, %{spec: sink_spec}})
      assert_receive(:spec_started)
      sink_pid = get_child_pid(:sink, pipeline)
      send(pipeline, {:start_spec, %{spec: links_spec}})
      assert_receive(:spec_started)
      bin_pid = get_child_pid(:bin, pipeline)
      source_pid = get_child_pid(:source, bin_pid)
      source_ref = Process.monitor(source_pid)
      Testing.Pipeline.play(pipeline)

      assert_pipeline_playback_changed(pipeline, _, :playing)
      Process.exit(sink_pid, :kill)
      assert_pipeline_crash_group_down(pipeline, :group_2)

      # Source has a static pad so it should crash when this pad is being unlinked while being
      # in playing state. If source crashes with proper error it means that :handle_unlink message
      # has been properly forwarded by a bin.
      assert_receive(
        {:DOWN, ^source_ref, :process, ^source_pid,
         {%Membrane.LinkError{
            message:
              "Tried to unlink static pad output while :source was in or was transitioning to playback state playing."
          }, _localization}}
      )
    end
  end

  test "element should crash when its neighbor connected via static pad crashes", %{
    pipeline: pipeline
  } do
    spec_1 = %Membrane.ParentSpec{
      children: [
        source: %Testing.Source{output: ['a', 'b', 'c']}
      ],
      crash_group: {:group_1, :temporary}
    }

    spec_2 = %Membrane.ParentSpec{
      children: [
        sink: Testing.Sink
      ],
      crash_group: {:group_2, :temporary}
    }

    links_spec = %Membrane.ParentSpec{
      links: [
        link(:source) |> to(:sink)
      ]
    }

    send(pipeline, {:start_spec, %{spec: spec_1}})
    assert_receive(:spec_started)
    send(pipeline, {:start_spec, %{spec: spec_2}})
    assert_receive(:spec_started)
    send(pipeline, {:start_spec_and_kill, %{spec: links_spec, children_to_kill: [:sink]}})
    assert_receive(:spec_started)

    assert_pipeline_crash_group_down(pipeline, :group_1)
    assert_pipeline_crash_group_down(pipeline, :group_2)
  end

  test "element shouldn't crash when its neighbor connected via dynamic pad crashes", %{
    pipeline: pipeline
  } do
    spec_1 = %Membrane.ParentSpec{
      children: [
        source: %Testing.DynamicSource{output: ['a', 'b', 'c']}
      ],
      crash_group: {:group_1, :temporary}
    }

    spec_2 = %Membrane.ParentSpec{
      children: [
        sink: Testing.Sink
      ],
      crash_group: {:group_2, :temporary}
    }

    links_spec = %Membrane.ParentSpec{
      links: [
        link(:source) |> to(:sink)
      ]
    }

    send(pipeline, {:start_spec, %{spec: spec_1}})
    assert_receive(:spec_started)
    send(pipeline, {:start_spec, %{spec: spec_2}})
    assert_receive(:spec_started)
    send(pipeline, {:start_spec_and_kill, %{spec: links_spec, children_to_kill: [:sink]}})
    assert_receive(:spec_started)

    refute_pipeline_crash_group_down(pipeline, :group_1)
    assert_pipeline_crash_group_down(pipeline, :group_2)
  end

  test "pipeline playback state should change successfully after spec with links has been returned",
       %{pipeline: pipeline} do
    bin_spec = %Membrane.ParentSpec{
      children: [
        bin: %Bin{child: %Testing.Source{output: ['a', 'b', 'c']}}
      ],
      crash_group: {:group_1, :temporary}
    }

    sink_spec = %Membrane.ParentSpec{
      children: [
        sink: Testing.Sink
      ],
      crash_group: {:group_2, :temporary}
    }

    links_spec = %Membrane.ParentSpec{
      links: [
        link(:bin) |> to(:sink)
      ]
    }

    send(pipeline, {:start_spec, %{spec: bin_spec}})
    assert_receive(:spec_started)
    send(pipeline, {:start_spec, %{spec: sink_spec}})
    assert_receive(:spec_started)
    send(pipeline, {:start_spec, %{spec: links_spec}})
    assert_receive(:spec_started)
    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)
  end

  defp get_child_pid(ref, parent_pid) do
    state = :sys.get_state(parent_pid)
    state.children[ref].pid
  end
end
