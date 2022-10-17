defmodule Membrane.Core.BinTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions

  alias Membrane.Core.Bin
  alias Membrane.Core.Message
  alias Membrane.Support.Bin.TestBins
  alias Membrane.Support.Bin.TestBins.{TestDynamicPadFilter, TestFilter}
  alias Membrane.Testing

  require Membrane.Core.Message

  describe "Starting and transmitting buffers" do
    test "in simple, flat use case" do
      buffers = ['a', 'b', 'c']

      children = [
        source: %Testing.Source{output: buffers},
        test_bin: %TestBins.SimpleBin{
          filter1: TestFilter,
          filter2: TestFilter
        },
        sink: Testing.Sink
      ]

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          structure: Membrane.ChildrenSpec.link_linear(children)
        )

      assert_data_flows_through(pipeline, buffers)
    end

    test "when bin is next to a bin" do
      buffers = ['a', 'b', 'c']

      children = [
        source: %Testing.Source{output: buffers},
        test_bin1: %TestBins.SimpleBin{
          filter1: TestFilter,
          filter2: TestFilter
        },
        test_bin2: %TestBins.SimpleBin{
          filter1: TestFilter,
          filter2: TestFilter
        },
        sink: Testing.Sink
      ]

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          structure: Membrane.ChildrenSpec.link_linear(children)
        )

      assert_data_flows_through(pipeline, buffers)
    end

    test "when bins are nested" do
      buffers = ['a', 'b', 'c']

      children = [
        source: %Testing.Source{output: buffers},
        test_bin: %TestBins.SimpleBin{
          filter1: TestFilter,
          filter2: %TestBins.SimpleBin{
            filter1: TestFilter,
            filter2: TestFilter
          }
        },
        sink: Testing.Sink
      ]

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          structure: Membrane.ChildrenSpec.link_linear(children)
        )

      assert_data_flows_through(pipeline, buffers)
    end

    test "when there are consecutive bins that are nested" do
      buffers = ['a', 'b', 'c']

      children = [
        source: %Testing.Source{output: buffers},
        test_bin: %TestBins.SimpleBin{
          filter1: %TestBins.SimpleBin{
            filter1: TestFilter,
            filter2: TestFilter
          },
          filter2: %TestBins.SimpleBin{
            filter1: TestFilter,
            filter2: TestFilter
          }
        },
        sink: Testing.Sink
      ]

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          structure: Membrane.ChildrenSpec.link_linear(children)
        )

      assert_data_flows_through(pipeline, buffers)
    end

    test "when pipeline has only one element being a padless bin" do
      buffers = ['a', 'b', 'c']

      children = [
        test_bin: %TestBins.TestPadlessBin{
          source: %Testing.Source{output: buffers},
          sink: Testing.Sink
        }
      ]

      pipeline = Testing.Pipeline.start_link_supervised!(structure: children)

      assert_pipeline_play(pipeline)

      assert_pipeline_notified(pipeline, :test_bin, {:handle_element_start_of_stream, :sink, _})

      assert_buffers_flow_through(pipeline, buffers, :test_bin)

      assert_pipeline_notified(pipeline, :test_bin, {:handle_element_end_of_stream, :sink, _})
    end

    test "when bin is a sink bin" do
      buffers = ['a', 'b', 'c']

      children = [
        source: %Testing.Source{output: buffers},
        test_bin: %TestBins.TestSinkBin{
          filter: TestFilter,
          sink: Testing.Sink
        }
      ]

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          structure: Membrane.ChildrenSpec.link_linear(children)
        )

      assert_pipeline_play(pipeline)

      assert_pipeline_notified(
        pipeline,
        :test_bin,
        {:handle_element_start_of_stream, :filter, _}
      )

      assert_pipeline_notified(pipeline, :test_bin, {:handle_element_start_of_stream, :sink, _})

      assert_buffers_flow_through(pipeline, buffers, :test_bin)

      assert_pipeline_notified(pipeline, :test_bin, {:handle_element_end_of_stream, :filter, _})
      assert_pipeline_notified(pipeline, :test_bin, {:handle_element_end_of_stream, :sink, _})
    end
  end

  describe "Handling DOWN messages" do
    test "DOWN message should be delivered to handle_info" do
      {:ok, bin_pid} =
        self()
        |> bin_init_options()
        |> Bin.start()

      monitored_proc = spawn(fn -> receive do: (:exit -> :ok) end)
      on_exit(fn -> send(monitored_proc, :exit) end)
      ref = Process.monitor(monitored_proc)

      send(bin_pid, {:DOWN, ref, :process, monitored_proc, :normal})

      assert_receive Message.new(:child_notification, [
                       :name,
                       {:DOWN, ^ref, :process, ^monitored_proc, :normal}
                     ])

      assert Process.alive?(bin_pid)
    end
  end

  describe "Dynamic pads" do
    test "handle_pad_added is called for dynamic pads" do
      alias Membrane.Pad
      require Pad
      buffers = ['a', 'b', 'c']

      children = [
        source: %Testing.Source{output: buffers},
        test_bin: %TestBins.TestDynamicPadBin{
          filter1: %TestBins.TestDynamicPadBin{
            filter1: TestDynamicPadFilter,
            filter2: TestDynamicPadFilter
          },
          filter2: %TestBins.TestDynamicPadBin{
            filter1: TestDynamicPadFilter,
            filter2: TestDynamicPadFilter
          }
        },
        sink: Testing.Sink
      ]

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          structure: Membrane.ChildrenSpec.link_linear(children)
        )

      Process.sleep(2000)
      assert_data_flows_through(pipeline, buffers)
      assert_pipeline_notified(pipeline, :test_bin, {:handle_pad_added, Pad.ref(:input, _)})
      assert_pipeline_notified(pipeline, :test_bin, {:handle_pad_added, Pad.ref(:output, _)})

      refute_pipeline_notified(pipeline, :test_bin, {:handle_pad_added, _})
    end
  end

  describe "Integration with clocks" do
    defmodule ClockElement do
      use Membrane.Source

      def_output_pad :output, caps_pattern: _any

      def_clock()
    end

    defmodule ClockBin do
      use Membrane.Bin

      def_clock()

      @impl true
      def handle_init(_options) do
        children = [element_child: ClockElement]

        spec = %Membrane.ChildrenSpec{
          structure: children,
          clock_provider: :element_child
        }

        {{:ok, spec: spec}, :ignored}
      end
    end

    defmodule ClockPipeline do
      use Membrane.Pipeline

      @impl true
      def handle_init(_options) do
        children = [bin_child: ClockBin]

        {{:ok, spec: %Membrane.ChildrenSpec{structure: children, clock_provider: :bin_child}},
         :ignored}
      end
    end

    test "Bin is clock_provider" do
      {:ok, _supervisor, pid} = ClockPipeline.start_link()

      %Membrane.Core.Pipeline.State{synchronization: %{clock_provider: pipeline_clock_provider}} =
        state = :sys.get_state(pid)

      assert %{choice: :manual, clock: clock1, provider: :bin_child} = pipeline_clock_provider
      refute is_nil(clock1)

      %{pid: bin_pid} = state.children[:bin_child]

      %Membrane.Core.Bin.State{synchronization: %{clock_provider: bin_clock_provider}} =
        :sys.get_state(bin_pid)

      assert %{choice: :manual, clock: clock2, provider: :element_child} = bin_clock_provider
      refute is_nil(clock2)

      assert proxy_for?(clock1, clock2)
      ClockPipeline.terminate(pid, blocking?: true)
    end

    test "handle_parent_notification/3 works for Bin" do
      buffers = ['a', 'b', 'c']

      children = [
        source: %Testing.Source{output: buffers},
        test_bin: TestBins.NotifyingParentBin,
        sink: Testing.Sink
      ]

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          structure: Membrane.ChildrenSpec.link_linear(children)
        )

      Testing.Pipeline.execute_actions(pipeline, notify_child: {:test_bin, "Some notification"})
      assert_pipeline_notified(pipeline, :test_bin, msg)
      assert msg == {"filter1", "Some notification"}
    end

    defp proxy_for?(c1, c2) do
      c1_state = :sys.get_state(c1)
      assert c1_state.proxy_for == c2
    end
  end

  defp assert_data_flows_through(pipeline, buffers, receiving_element \\ :sink) do
    assert_pipeline_play(pipeline)

    assert_start_of_stream(pipeline, ^receiving_element)

    assert_buffers_flow_through(pipeline, buffers, receiving_element)

    assert_end_of_stream(pipeline, ^receiving_element)
  end

  defp assert_buffers_flow_through(pipeline, buffers, receiving_element) do
    buffers
    |> Enum.each(fn b ->
      assert_sink_buffer(pipeline, receiving_element, %Membrane.Buffer{payload: ^b})
    end)
  end

  defp bin_init_options(pipeline) do
    %{
      name: :name,
      module: TestBins.SimpleBin,
      node: nil,
      parent: pipeline,
      parent_clock: nil,
      parent_path: [],
      log_metadata: [],
      user_options: %{
        filter1: TestFilter,
        filter2: TestFilter
      },
      children_supervisor: Membrane.Core.ChildrenSupervisor.start_link!()
    }
  end
end
