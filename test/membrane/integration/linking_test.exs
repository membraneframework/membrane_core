defmodule Membrane.Integration.LinkingTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions
  import Membrane.ParentSpec

  alias Membrane.{Buffer, ParentSpec, Testing}
  alias Membrane.Support.Element.DynamicFilter

  require Membrane.Pad, as: Pad

  defmodule Bin do
    use Membrane.Bin

    def_options child: [spec: struct() | module()],
                remove_child_on_unlink: [spec: boolean(), default: true]

    def_output_pad :output, demand_unit: :buffers, caps: :any, availability: :on_request

    @impl true
    def handle_init(_ctx, opts) do
      children = [
        source: opts.child
      ]

      spec = %ParentSpec{
        children: children
      }

      {{:ok, spec: spec}, Map.from_struct(opts)}
    end

    @impl true
    def handle_pad_added(pad, _ctx, state) do
      links = [
        link(:source) |> to_bin_output(pad)
      ]

      spec = %ParentSpec{
        links: links
      }

      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_pad_removed(_pad, _ctx, state) do
      remove_child = if state.remove_child_on_unlink, do: [remove_child: :source], else: []
      {{:ok, remove_child ++ [notify_parent: :handle_pad_removed]}, %{}}
    end
  end

  defmodule Pipeline do
    @moduledoc false
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, opts) do
      {:ok, %{testing_pid: opts.testing_pid}}
    end

    @impl true
    def handle_info({:start_spec, %{spec: spec}}, _ctx, state) do
      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_info(
          {:start_spec_and_kill, %{spec: spec, children_to_kill: children_to_kill}},
          ctx,
          state
        ) do
      Enum.each(children_to_kill, &Process.exit(ctx.children[&1].pid, :kill))
      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_info({:remove_child, child}, _ctx, state) do
      {{:ok, remove_child: child}, state}
    end

    @impl true
    def handle_info(_msg, _ctx, state) do
      {:ok, state}
    end

    @impl true
    def handle_spec_started(_children, _ctx, state) do
      send(state.testing_pid, :spec_started)
      {:ok, state}
    end
  end

  setup do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        module: Pipeline,
        custom_args: %{testing_pid: self()}
      )

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
      Testing.Pipeline.execute_actions(pipeline, playback: :playing)
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: 'a'})
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: 'b'})
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: 'c'})
      send(pipeline, {:remove_child, :sink})
      assert_pipeline_notified(pipeline, :bin, :handle_pad_removed)
    end

    test "and element crashes, bin forwards the unlink message to child", %{pipeline: pipeline} do
      bin_spec = %Membrane.ParentSpec{
        children: [
          bin: %Bin{
            child: %Testing.Source{output: ['a', 'b', 'c']},
            remove_child_on_unlink: false
          }
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
      Testing.Pipeline.execute_actions(pipeline, playback: :playing)

      assert_pipeline_play(pipeline)
      Process.exit(sink_pid, :kill)
      assert_pipeline_crash_group_down(pipeline, :group_2)

      # Source has a static pad so it should crash when this pad is being unlinked while being
      # in playing state. If source crashes with proper error it means that :handle_unlink message
      # has been properly forwarded by a bin.
      assert_receive {:DOWN, ^source_ref, :process, ^source_pid,
                      {%Membrane.PadError{message: message}, _localization}}

      assert message =~ ~r/static.*pad.*unlink/u
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

  test "pipeline playback should change successfully after spec with links has been returned",
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
    Testing.Pipeline.execute_actions(pipeline, playback: :playing)
    assert_pipeline_play(pipeline)
  end

  defmodule SlowSetupSink do
    use Membrane.Sink

    def_input_pad :input, caps: :any, demand_mode: :auto

    def_options setup_delay: [spec: non_neg_integer()]

    @impl true
    def handle_setup(_ctx, state) do
      Process.sleep(state.setup_delay)
      {:ok, state}
    end
  end

  @doc """
  In this scenario, the first spec has a delay in initialization, so it should be linked
  after the second spec (the one with `independent_*` children). The last spec has a link to
  the `filter`, which is spawned in the first spec, so it has to wait till the first spec is linked.
  """
  test "Children are linked in proper order" do
    pipeline = Testing.Pipeline.start_link_supervised!()

    Testing.Pipeline.execute_actions(pipeline,
      spec: %ParentSpec{
        links: [
          link(:src1, %Testing.Source{output: []})
          |> via_in(Pad.ref(:input, 1))
          |> to(:filter, DynamicFilter)
          |> via_out(Pad.ref(:output, 1))
          |> to(:sink1, %SlowSetupSink{setup_delay: 300})
        ]
      },
      spec: %ParentSpec{
        links: [
          link(:independent_src, %Testing.Source{output: []})
          |> to(:independent_filter, DynamicFilter)
          |> to(:independent_sink, Testing.Sink)
        ]
      },
      spec: %ParentSpec{
        links: [
          link(:src2, %Testing.Source{output: []})
          |> via_in(Pad.ref(:input, 2))
          |> to(:filter)
          |> via_out(Pad.ref(:output, 2))
          |> to(:sink2, Testing.Sink)
        ]
      }
    )

    assert [
             independent_filter: Pad.ref(:input, _input_id),
             independent_filter: Pad.ref(:output, _output_id),
             filter: Pad.ref(:input, 1),
             filter: Pad.ref(:output, 1),
             filter: Pad.ref(:input, 2),
             filter: Pad.ref(:output, 2)
           ] =
             Enum.map(1..6, fn _i ->
               assert_receive {Testing.Pipeline, ^pipeline,
                               {:handle_child_notification, {{:pad_added, pad}, element}}}

               {element, pad}
             end)
  end

  test "Elements and bins can be spawned, linked and removed" do
    alias Membrane.Support.Bin.TestBins.{TestDynamicPadBin, TestFilter}
    pipeline = Testing.Pipeline.start_link_supervised!()

    Testing.Pipeline.execute_actions(pipeline,
      spec: %ParentSpec{
        links: [
          link(:source, %Testing.Source{output: [1, 2, 3]})
          |> to(:filter1, %TestDynamicPadBin{
            filter1: %TestDynamicPadBin{filter1: TestFilter, filter2: TestFilter},
            filter2: TestFilter
          })
          |> to(:filter2, %TestDynamicPadBin{
            filter1: %TestDynamicPadBin{
              filter1: TestFilter,
              filter2: %TestDynamicPadBin{filter1: TestFilter, filter2: TestFilter}
            },
            filter2: %TestDynamicPadBin{filter1: TestFilter, filter2: TestFilter}
          })
          |> to(:sink, Testing.Sink)
        ]
      }
    )

    assert_end_of_stream(pipeline, :sink)
    Membrane.Pipeline.terminate(pipeline, blocking?: true)
  end

  defp get_child_pid(ref, parent_pid) do
    state = :sys.get_state(parent_pid)
    state.children[ref].pid
  end
end
