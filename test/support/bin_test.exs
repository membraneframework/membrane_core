defmodule Membrane.Core.BinTest do
  use ExUnit.Case, async: true

  alias Membrane.Testing
  alias Membrane.Support.Bin.TestBins

  import Membrane.Testing.Assertions

  defmodule TestFilter do
    use Membrane.Filter

    def_output_pad :output, caps: :any

    def_input_pad :input, demand_unit: :buffers, caps: :any

    @impl true
    def handle_other({:notify_parent, notif}, _ctx, state), do: {{:ok, notify: notif}, state}

    @impl true
    def handle_demand(:output, size, _, _ctx, state), do: {{:ok, demand: {:input, size}}, state}

    @impl true
    def handle_process(_pad, buf, _, state), do: {{:ok, buffer: {:output, buf}}, state}
  end

  describe "Starting and transmitting buffers" do
    test "in simple, flat use case" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            source: %Testing.Source{output: buffers},
            test_bin: %TestBins.SimpleBin{
              filter1: TestFilter,
              filter2: TestFilter
            },
            sink: Testing.Sink
          ]
        })

      assert_data_flows_through(pipeline, buffers)
    end

    test "when bin is next to a bin" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
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
        })

      assert_data_flows_through(pipeline, buffers)
    end

    test "when bins are nested" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
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
        })

      assert_data_flows_through(pipeline, buffers)
    end

    test "when there are consecutive bins that are nested" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
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
        })

      assert_data_flows_through(pipeline, buffers)
    end

    test "when pipeline has only one element being a padless bin" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            test_bin: %TestBins.TestPadlessBin{
              source: %Testing.Source{output: buffers},
              sink: Testing.Sink
            }
          ]
        })

      assert_playing(pipeline)

      assert_pipeline_notified(pipeline, :test_bin, {:handle_element_start_of_stream, {:sink, _}})

      assert_buffers_flow_through(pipeline, buffers, :test_bin)

      assert_pipeline_notified(pipeline, :test_bin, {:handle_element_end_of_stream, {:sink, _}})
    end

    test "when bin is a sink bin" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            source: %Testing.Source{output: buffers},
            test_bin: %TestBins.TestSinkBin{
              filter: TestFilter,
              sink: Testing.Sink
            }
          ]
        })

      assert_playing(pipeline)

      assert_pipeline_notified(
        pipeline,
        :test_bin,
        {:handle_element_start_of_stream, {:filter, _}}
      )

      assert_pipeline_notified(pipeline, :test_bin, {:handle_element_start_of_stream, {:sink, _}})

      assert_buffers_flow_through(pipeline, buffers, :test_bin)

      assert_pipeline_notified(pipeline, :test_bin, {:handle_element_end_of_stream, {:filter, _}})
      assert_pipeline_notified(pipeline, :test_bin, {:handle_element_end_of_stream, {:sink, _}})
    end
  end

  describe "Events passing in pipeline" do
    test "notifications are handled by bin as if it's a pipeline" do
      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            source: Testing.Source,
            test_bin: %TestBins.SimpleBin{
              filter1: TestFilter,
              filter2: TestFilter
            },
            sink: %Testing.Sink{autodemand: false}
          ]
        })

      :ok = Testing.Pipeline.play(pipeline)

      assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
      assert_pipeline_playback_changed(pipeline, :prepared, :playing)

      {:ok, filter1_pid} = get_child_pid(pipeline, [:test_bin, :filter1])

      send(filter1_pid, {:notify_parent, :some_example_notification})

      # As this test's implementation of bin only passes notifications up
      assert_pipeline_notified(pipeline, :test_bin, :some_example_notification)
    end
  end

  describe "Dynamic pads" do
    test "allow bin to be started and work properly" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            source: %Testing.Source{output: buffers},
            test_bin: %TestBins.TestDynamicPadBin{
              filter1: TestFilter,
              filter2: TestFilter
            },
            sink: Testing.Sink
          ]
        })

      assert_data_flows_through(pipeline, buffers)
    end
  end

  defp get_child_pid(last_child_pid, []) when is_pid(last_child_pid) do
    {:ok, last_child_pid}
  end

  defp get_child_pid(last_child_pid, [child | children]) when is_pid(last_child_pid) do
    state = :sys.get_state(last_child_pid)
    %{pid: child_pid} = state.children[child]
    get_child_pid(child_pid, children)
  end

  defp get_child_pid(_, _) do
    {:error, :child_was_not_found}
  end

  defp assert_data_flows_through(pipeline, buffers, receiving_element \\ :sink) do
    assert_playing(pipeline)

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

  defp assert_playing(pipeline) do
    :ok = Testing.Pipeline.play(pipeline)

    assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)
  end
end
