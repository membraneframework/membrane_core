defmodule Membrane.Integration.LinkingTest do
  use ExUnit.Case, async?: true

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.{Buffer, Child, ChildrenSpec, Testing}
  alias Membrane.Support.Element.DynamicFilter

  require Membrane.Pad, as: Pad

  defmodule Bin do
    use Membrane.Bin

    def_options child: [spec: struct() | module()],
                remove_child_on_unlink: [spec: boolean(), default: true]

    def_output_pad :output,
      demand_unit: :buffers,
      accepted_format: _any,
      availability: :on_request

    @impl true
    def handle_init(_ctx, opts) do
      children = [
        child(:source, opts.child)
      ]

      {[spec: children], Map.from_struct(opts)}
    end

    @impl true
    def handle_pad_added(pad, _ctx, state) do
      links = [
        get_child(:source) |> bin_output(pad)
      ]

      {[spec: links], state}
    end

    @impl true
    def handle_pad_removed(_pad, _ctx, state) do
      remove_child = if state.remove_child_on_unlink, do: [remove_children: :source], else: []
      {remove_child ++ [notify_parent: :handle_pad_removed], %{}}
    end
  end

  defmodule Pipeline do
    @moduledoc false
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, opts) do
      {[], %{testing_pid: opts.testing_pid}}
    end

    @impl true
    def handle_info({:start_spec, %{spec: spec}}, _ctx, state) do
      {[spec: spec], state}
    end

    @impl true
    def handle_info(
          {:start_spec_and_kill, %{spec: spec, children_to_kill: children_to_kill}},
          ctx,
          state
        ) do
      Enum.each(children_to_kill, &Process.exit(ctx.children[&1].pid, :kill))
      {[spec: spec], state}
    end

    @impl true
    def handle_info({:remove_children, child}, _ctx, state) do
      {[remove_children: child], state}
    end

    @impl true
    def handle_info(_msg, _ctx, state) do
      {[], state}
    end

    @impl true
    def handle_spec_started(_children, _ctx, state) do
      send(state.testing_pid, :spec_started)
      {[], state}
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
      spec = [
        child(:bin, %Bin{child: %Testing.Source{output: ['a', 'b', 'c']}}),
        child(:sink, Testing.Sink),
        get_child(:bin) |> get_child(:sink)
      ]

      send(pipeline, {:start_spec, %{spec: spec}})
      assert_receive(:spec_started)
      Testing.Pipeline.execute_actions(pipeline, playback: :playing)
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: 'a'})
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: 'b'})
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: 'c'})
      send(pipeline, {:remove_children, :sink})
      assert_pipeline_notified(pipeline, :bin, :handle_pad_removed)
    end

    test "and element crashes, bin forwards the unlink message to child", %{pipeline: pipeline} do
      bin_spec = {
        child(:bin, %Bin{
          child: %Testing.Source{output: ['a', 'b', 'c']},
          remove_child_on_unlink: false
        }),
        crash_group_mode: :temporary, group: :group_1
      }

      sink_spec = {
        child(:sink, Testing.Sink),
        crash_group_mode: :temporary, group: :group_2
      }

      links_spec =
        get_child(Child.ref(:bin, group: :group_1))
        |> get_child(Child.ref(:sink, group: :group_2))

      send(pipeline, {:start_spec, %{spec: bin_spec}})
      assert_receive(:spec_started)
      send(pipeline, {:start_spec, %{spec: sink_spec}})
      assert_receive(:spec_started)
      sink_pid = get_child_pid({Membrane.Child, :group_2, :sink}, pipeline)
      send(pipeline, {:start_spec, %{spec: links_spec}})
      assert_receive(:spec_started)
      bin_pid = get_child_pid({Membrane.Child, :group_1, :bin}, pipeline)
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
    spec_1 = {
      child(:source, %Testing.Source{output: ['a', 'b', 'c']}),
      group: :group_1, crash_group_mode: :temporary
    }

    spec_2 = {child(:sink, Testing.Sink), group: :group_2, crash_group_mode: :temporary}

    links_spec =
      get_child(Child.ref(:source, group: :group_1))
      |> get_child(Child.ref(:sink, group: :group_2))

    send(pipeline, {:start_spec, %{spec: spec_1}})
    assert_receive(:spec_started)
    send(pipeline, {:start_spec, %{spec: spec_2}})
    assert_receive(:spec_started)

    send(
      pipeline,
      {:start_spec_and_kill,
       %{
         spec: links_spec,
         children_to_kill: [{Membrane.Child, :group_2, :sink}]
       }}
    )

    assert_receive(:spec_started)

    assert_pipeline_crash_group_down(pipeline, :group_1)
    assert_pipeline_crash_group_down(pipeline, :group_2)
  end

  test "element shouldn't crash when its neighbor connected via dynamic pad crashes", %{
    pipeline: pipeline
  } do
    spec_1 = {
      child(:source, %Testing.DynamicSource{output: ['a', 'b', 'c']}),
      group: :group_1, crash_group_mode: :temporary
    }

    spec_2 = {
      child(:sink, Testing.Sink),
      group: :group_2, crash_group_mode: :temporary
    }

    links_spec =
      get_child(Child.ref(:source, group: :group_1))
      |> get_child(Child.ref(:sink, group: :group_2))

    send(pipeline, {:start_spec, %{spec: spec_1}})
    assert_receive(:spec_started)
    send(pipeline, {:start_spec, %{spec: spec_2}})
    assert_receive(:spec_started)

    send(
      pipeline,
      {:start_spec_and_kill,
       %{
         spec: links_spec,
         children_to_kill: [{Membrane.Child, :group_2, :sink}]
       }}
    )

    assert_receive(:spec_started)

    refute_pipeline_crash_group_down(pipeline, :group_1)
    assert_pipeline_crash_group_down(pipeline, :group_2)
  end

  test "element shouldn't crash when its neighbor connected via dynamic pad crashes and the crash groups are set within nested spec",
       %{
         pipeline: pipeline
       } do
    spec_inner = {
      child(:sink, Testing.Sink),
      crash_group_mode: :temporary, group: :group_2
    }

    spec = {
      [spec_inner, child(:source, %Testing.DynamicSource{output: ['a', 'b', 'c']})],
      crash_group_mode: :temporary, group: :group_1
    }

    links_spec =
      get_child(Child.ref(:source, group: :group_1))
      |> get_child(Child.ref(:sink, group: :group_2))

    send(pipeline, {:start_spec, %{spec: spec}})
    assert_receive(:spec_started)

    send(
      pipeline,
      {:start_spec_and_kill,
       %{
         spec: links_spec,
         children_to_kill: [{Membrane.Child, :group_2, :sink}]
       }}
    )

    assert_receive(:spec_started)

    refute_pipeline_crash_group_down(pipeline, :group_1)
    assert_pipeline_crash_group_down(pipeline, :group_2)
  end

  test "pipeline playback should change successfully after spec with links has been returned",
       %{pipeline: pipeline} do
    bin_spec = {
      child(:bin, %Bin{child: %Testing.Source{output: ['a', 'b', 'c']}}),
      group: :group_1, crash_group_mode: :temporary
    }

    sink_spec = {
      child(:sink, Testing.Sink),
      group: :group_1, crash_group_mode: :temporary
    }

    links_spec =
      get_child(Child.ref(:bin, group: :group_1)) |> get_child(Child.ref(:sink, group: :group_1))

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

    def_input_pad :input, accepted_format: _any, demand_mode: :auto

    def_options setup_delay: [spec: non_neg_integer()]

    @impl true
    def handle_setup(_ctx, state) do
      Process.sleep(state.setup_delay)
      {[], state}
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
      spec: [
        child(:src1, %Testing.Source{output: []})
        |> via_in(Pad.ref(:input, 1))
        |> child(:filter, DynamicFilter)
        |> via_out(Pad.ref(:output, 1))
        |> child(:sink1, %SlowSetupSink{setup_delay: 300})
      ],
      spec: [
        child(:independent_src, %Testing.Source{output: []})
        |> child(:independent_filter, DynamicFilter)
        |> child(:independent_sink, Testing.Sink)
      ],
      spec: [
        child(:src2, %Testing.Source{output: []})
        |> via_in(Pad.ref(:input, 2))
        |> get_child(:filter)
        |> via_out(Pad.ref(:output, 2))
        |> child(:sink2, Testing.Sink)
      ]
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
      spec: [
        child(:source, %Testing.Source{output: [1, 2, 3]})
        |> child(:filter1, %TestDynamicPadBin{
          filter1: %TestDynamicPadBin{filter1: TestFilter, filter2: TestFilter},
          filter2: TestFilter
        })
        |> child(:filter2, %TestDynamicPadBin{
          filter1: %TestDynamicPadBin{
            filter1: TestFilter,
            filter2: %TestDynamicPadBin{filter1: TestFilter, filter2: TestFilter}
          },
          filter2: %TestDynamicPadBin{filter1: TestFilter, filter2: TestFilter}
        })
        |> child(:sink, Testing.Sink)
      ]
    )

    assert_end_of_stream(pipeline, :sink)
    Membrane.Pipeline.terminate(pipeline, blocking?: true)
  end

  test "Bin should crash if it doesn't link internally within timeout" do
    defmodule NoInternalLinkBin do
      use Membrane.Bin

      def_input_pad :input,
        availability: :on_request,
        accepted_format: _any,
        demand_unit: :buffers
    end

    pipeline =
      Testing.Pipeline.start_supervised!(
        structure: [child(:source, Testing.Source) |> child(:bin, NoInternalLinkBin)]
      )

    bin_pid = get_child_pid(:bin, pipeline)
    monitor = Process.monitor(bin_pid)
    assert_receive {:DOWN, ^monitor, :process, _pid, {%Membrane.LinkError{}, _stacktrace}}, 6000
  end

  defp get_child_pid(ref, parent_pid) do
    state = :sys.get_state(parent_pid)
    state.children[ref].pid
  end
end
