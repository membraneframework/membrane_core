defmodule Membrane.Integration.ChildRemovalTest do
  use Bunch
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions

  alias Membrane.Core.Message
  alias Membrane.Support.ChildRemovalTest
  alias Membrane.Testing

  require Message

  test "Element can be removed when pipeline is in stopped state" do
    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(
        module: ChildRemovalTest.Pipeline,
        custom_args: %{
          source: Testing.Source,
          filter1: ChildRemovalTest.Filter,
          filter2: ChildRemovalTest.Filter,
          filter3: ChildRemovalTest.Filter,
          sink: Testing.Sink
        }
      )

    Process.monitor(pipeline_pid)

    [filter_pid1, filter_pid2, filter_pid3] =
      [:filter1, :filter2, :filter3]
      |> Enum.map(&get_filter_pid(&1, pipeline_pid))

    ChildRemovalTest.Pipeline.remove_child(pipeline_pid, :filter2)

    assert_pid_dead(filter_pid2)
    assert_pid_alive(pipeline_pid)
    assert_pid_alive(filter_pid1)
    assert_pid_alive(filter_pid3)
  end

  test "Element can be removed when pipeline is in playing state" do
    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(
        module: ChildRemovalTest.Pipeline,
        custom_args: %{
          source: Testing.Source,
          filter1: ChildRemovalTest.Filter,
          filter2: ChildRemovalTest.Filter,
          filter3: ChildRemovalTest.Filter,
          sink: Testing.Sink
        }
      )

    Process.monitor(pipeline_pid)

    [filter_pid1, filter_pid2, filter_pid3] =
      [:filter1, :filter2, :filter3]
      |> Enum.map(&get_filter_pid(&1, pipeline_pid))

    assert_pipeline_play(pipeline_pid)
    assert_pipeline_notified(pipeline_pid, :filter1, :playing)
    assert_pipeline_notified(pipeline_pid, :filter2, :playing)
    assert_pipeline_notified(pipeline_pid, :filter3, :playing)

    ChildRemovalTest.Pipeline.remove_child(pipeline_pid, :filter2)

    assert_pid_dead(filter_pid2)
    assert_pid_alive(filter_pid1)
    assert_pid_alive(filter_pid3)
  end

  @doc """
  In this scenario we make `filter3` switch between prepare and playing state slowly
  so that it has to store incoming buffers in PlaybackBuffer. When the `filter1` dies,
  and `filter2` tries to actually enter playing it SHOULD NOT have any buffers there yet.

  source -- filter1 -- [input1] filter2 -- [input1] filter3 -- sink

  """
  test "When PlaybackBuffer is evaluated there is no buffers from removed element" do
    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(
        module: ChildRemovalTest.Pipeline,
        custom_args: %{
          source: Testing.Source,
          filter1: ChildRemovalTest.Filter,
          filter2: ChildRemovalTest.Filter,
          filter3: %ChildRemovalTest.Filter{playing_delay: prepared_to_playing_delay()},
          sink: Testing.Sink
        }
      )

    Process.monitor(pipeline_pid)

    [filter_pid1, filter_pid2, filter_pid3] =
      [:filter1, :filter2, :filter3]
      |> Enum.map(&get_filter_pid(&1, pipeline_pid))

    assert_pipeline_play(pipeline_pid)
    assert_pipeline_notified(pipeline_pid, :filter1, :playing)
    assert_pipeline_notified(pipeline_pid, :filter2, :playing)
    assert_pipeline_notified(pipeline_pid, :filter3, :playing)

    ChildRemovalTest.Pipeline.remove_child(pipeline_pid, :filter2)

    assert_pid_dead(filter_pid2)
    assert_pid_alive(filter_pid1)
    assert_pid_alive(filter_pid3)
  end

  describe "Children can defer being removed by not returning terminate from terminate request" do
    import Membrane.ChildrenSpec

    defmodule RemovalDeferSource do
      use Membrane.Source

      def_output_pad :output, flow_control: :push, accepted_format: _any

      @impl true
      def handle_init(_ctx, _opts) do
        Process.register(self(), __MODULE__)
        {[], %{}}
      end

      @impl true
      def handle_terminate_request(_ctx, state) do
        {[], state}
      end

      @impl true
      def handle_info(:terminate, _ctx, state) do
        {[terminate: :normal], state}
      end
    end

    defmodule RemovalDeferSink do
      use Membrane.Sink

      def_input_pad :input, flow_control: :auto, accepted_format: _any

      @impl true
      def handle_init(_ctx, _opts) do
        Process.register(self(), __MODULE__)
        {[], %{}}
      end

      @impl true
      def handle_terminate_request(_ctx, state) do
        {[], state}
      end

      @impl true
      def handle_info(:terminate, _ctx, state) do
        {[terminate: :normal], state}
      end
    end

    defmodule RemovalDeferBin do
      use Membrane.Bin

      def_options defer?: [spec: boolean], test_process: [spec: pid]

      def_output_pad :output, accepted_format: _any

      @impl true
      def handle_init(_ctx, opts) do
        Process.register(self(), __MODULE__)
        links = [child(:source, RemovalDeferSource) |> bin_output()]
        {[spec: links], Map.from_struct(opts)}
      end

      @impl true
      def handle_terminate_request(_ctx, %{defer?: true} = state) do
        send(state.test_process, {__MODULE__, :terminate_request})
        {[remove_children: :source], state}
      end

      @impl true
      def handle_terminate_request(ctx, %{defer?: false} = state) do
        send(state.test_process, {__MODULE__, :terminate_request})
        super(ctx, state)
      end

      @impl true
      def handle_info(:terminate, _ctx, state) do
        {[terminate: :normal], state}
      end
    end

    test "two linked elements" do
      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec: child(:source, RemovalDeferSource) |> child(:sink, RemovalDeferSink)
        )

      monitor = Process.monitor(pipeline)
      Testing.Pipeline.terminate(pipeline)
      assert %{module: Membrane.Core.Pipeline.Zombie} = :sys.get_state(pipeline)
      send(RemovalDeferSource, :terminate)
      send(RemovalDeferSink, :terminate)
      assert_receive {:DOWN, ^monitor, :process, _pid, :normal}
    end

    test "two linked elements, one in a bin" do
      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(:bin, %RemovalDeferBin{defer?: false, test_process: self()})
            |> child(:sink, RemovalDeferSink)
        )

      monitor = Process.monitor(pipeline)
      Testing.Pipeline.terminate(pipeline)
      assert %{module: Membrane.Core.Pipeline.Zombie} = :sys.get_state(pipeline)
      assert_receive {RemovalDeferBin, :terminate_request}
      assert %{module: Membrane.Core.Bin.Zombie} = :sys.get_state(RemovalDeferBin)
      send(RemovalDeferSource, :terminate)
      send(RemovalDeferSink, :terminate)
      assert_receive {:DOWN, ^monitor, :process, _pid, :normal}
    end

    @tag :target
    test "two linked elements, one in a bin that defers termination" do
      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(:bin, %RemovalDeferBin{defer?: true, test_process: self()})
            |> child(:sink, RemovalDeferSink)
        )

      pipeline_monitor = Process.monitor(pipeline)
      Testing.Pipeline.terminate(pipeline)
      assert %{module: Membrane.Core.Pipeline.Zombie} = :sys.get_state(pipeline)
      assert_receive {RemovalDeferBin, :terminate_request}
      assert %{module: RemovalDeferBin} = :sys.get_state(RemovalDeferBin)
      send(RemovalDeferSource, :terminate)
      bin_monitor = Process.monitor(RemovalDeferBin)
      send(RemovalDeferBin, :terminate)
      assert_receive {:DOWN, ^bin_monitor, :process, _pid, :normal}
      send(RemovalDeferSink, :terminate)
      assert_receive {:DOWN, ^pipeline_monitor, :process, _pid, :normal}
    end
  end

  test "If all the children from the children group are removed" do
    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(module: ChildRemovalTest.ChildRemovingPipeline)

    Testing.Pipeline.execute_actions(pipeline_pid, [
      {:remove_children, :first_crash_group}
    ])

    assert_pipeline_notified(
      pipeline_pid,
      :source,
      {:pad_removed, {Membrane.Pad, :first, _ref}}
    )

    assert_pipeline_notified(
      pipeline_pid,
      :source,
      {:pad_removed, {Membrane.Pad, :second, _ref}}
    )

    assert_pipeline_notified(
      pipeline_pid,
      :source,
      {:pad_removed, {Membrane.Pad, :third, _ref}}
    )

    refute_pipeline_notified(
      pipeline_pid,
      :source,
      {:pad_removed, {Membrane.Pad, :fourth, _ref}}
    )

    refute_pipeline_notified(
      pipeline_pid,
      :source,
      {:pad_removed, {Membrane.Pad, :fifth, _ref}}
    )
  end

  defmodule DynamicElement do
    use Membrane.Endpoint

    def_input_pad :input, flow_control: :push, accepted_format: _any, availability: :on_request
    def_output_pad :output, flow_control: :push, accepted_format: _any, availability: :on_request
    def_options test_process: [spec: pid()]

    #  await_on_pad_added: [spec: boolean(), default: false],
    #  wait_on_pad_added: [spec: boolean(), default: true]

    @impl true
    def handle_init(ctx, opts) do
      send(opts.test_process, {:init, ctx.name, self()})
      {[], Map.from_struct(opts)}
    end

    @impl true
    def handle_pad_added(_pad, ctx, state) do
      # if state.await_on_pad_added do
      #   receive do
      #     :add_pad -> :ok
      #   end
      # end

      send(state.test_process, {:pad_added, ctx.name, self()})
      {[], state}
    end

    @impl true
    def handle_pad_removed(_pad, ctx, state) do
      send(state.test_process, {:pad_removed, ctx.name, self()})
      {[], state}
    end

    @impl true
    def handle_info({:terminate, reason}, _ctx, state) do
      {[terminate: reason], state}
    end

    @impl true
    def handle_terminate_request(ctx, state) do
      send(state.test_process, {:terminate_request, ctx.name, self()})
      {[], state}
    end
  end

  defmodule InvalidBin do
    use Membrane.Bin

    def_output_pad :output, accepted_format: _any, availability: :on_request
    def_options test_process: [spec: pid()]

    @impl true
    def handle_init(ctx, opts) do
      send(opts.test_process, {:init, ctx.name, self()})
      {[], Map.from_struct(opts)}
    end

    @impl true
    def handle_pad_added(_pad, _ctx, state), do: {[], state}
  end

  describe "1 " do
    import Membrane.ChildrenSpec
    require Membrane.Child, as: Child

    @tag :dupa
    test "A" do

      pipeline = Testing.Pipeline.start_link_supervised!(
        spec:
          child(:bin, %InvalidBin{test_process: self()})
          |> child(:sink, %DynamicElement{test_process: self()})
      )

      assert_receive {:init, :sink, _sink_pid}
      assert_receive {:init, :bin, bin_pid}

      monitor_ref = Process.monitor(bin_pid)
      Testing.Pipeline.execute_actions(pipeline, remove_children: :sink)

      assert_receive {:terminate_request, :sink, _sink_pid}
      refute_receive {:DOWN, ^monitor_ref, :process, ^bin_pid, _reason}, 500

      Testing.Pipeline.terminate(pipeline, blocking?: true)
    end

    @tag :dupa
    test "B" do
      pipeline = Testing.Pipeline.start_link_supervised!(
        spec:
          child(:bin, %InvalidBin{test_process: self()})
          |> child(:sink, %DynamicElement{test_process: self()})
      )

      assert_receive {:init, :sink, sink_pid}
      assert_receive {:init, :bin, bin_pid}

      monitor_ref = Process.monitor(bin_pid)
      send(sink_pid, {:terminate, :normal})

      refute_receive {:DOWN, ^monitor_ref, :process, ^bin_pid, _reason}, 500

      Testing.Pipeline.terminate(pipeline, blocking?: true)
    end


    @tag :dupa
    test "C" do
      sink_ref = Child.ref(:sink, group: :group)

      pipeline = Testing.Pipeline.start_link_supervised!(
        spec: [
          {child(:sink, %DynamicElement{test_process: self()}), group: :group, crash_group_mode: :temporary},
          child(:bin, %InvalidBin{test_process: self()})
          |> get_child(sink_ref)
        ]
      )

      assert_receive {:init, ^sink_ref, sink_pid}
      assert_receive {:init, :bin, bin_pid}

      bin_monitor_ref = Process.monitor(bin_pid)
      sink_monitor_ref = Process.monitor(sink_pid)

      send(sink_pid, {:terminate, :reason})

      assert_receive {:DOWN, ^sink_monitor_ref, :process, ^sink_pid, _reason}
      refute_receive {:DOWN, ^bin_monitor_ref, :process, ^bin_pid, _reason}, 500

      Testing.Pipeline.terminate(pipeline, blocking?: true)
    end
  end

  #############
  ## HELPERS ##
  #############

  defp assert_pid_dead(pid) do
    assert_receive {:DOWN, _, :process, ^pid, :normal}
  end

  defp assert_pid_alive(pid) do
    refute_receive {:DOWN, _, :process, ^pid, _}
  end

  defp get_filter_pid(ref, pipeline_pid) do
    state = :sys.get_state(pipeline_pid)
    pid = state.children[ref].pid
    Process.monitor(pid)
    pid
  end

  defp prepared_to_playing_delay, do: 300
end
