defmodule Membrane.Integration.SyncTest do
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions

  alias Membrane.Support.{Sync, TestBins}
  alias Membrane.{Time, Testing}
  alias TestBins.TestFilter

  @tick_number_error 5
  @sync_error_ms 5
  @timeout 500

  @tag :long_running
  test "When ratio = 1 amount of lost ticks is roughly the same regardless of the time of transmission" do
    tick_interval = 1

    assert {:ok, pipeline} =
             Testing.Pipeline.start_link(%Testing.Pipeline.Options{
               elements: [
                 source: %Sync.Source{
                   tick_interval: tick_interval |> Time.milliseconds(),
                   test_process: self()
                 },
                 sink: Sync.Sink
               ]
             })

    for tries <- [100, 1000, 10000] do
      Testing.Pipeline.play(pipeline)

      assert_pipeline_playback_changed(pipeline, :prepared, :playing)
      Process.sleep(tick_interval * tries)

      Testing.Pipeline.stop(pipeline)

      ticks_amount = receive_ticks(pipeline)

      assert_in_delta ticks_amount, tries, @tick_number_error
    end
  end

  @tag :long_running
  test "Ratio modifies ticking pace correctly" do
    tick_interval = 100
    tries = 300
    ratio_error = 0.1

    actual_report_interval = 100
    reported_interval = 300

    assert {:ok, pipeline} =
             Testing.Pipeline.start_link(%Testing.Pipeline.Options{
               elements: [
                 source: %Sync.Source{
                   tick_interval: tick_interval |> Time.milliseconds(),
                   test_process: self()
                 },
                 sink: Sync.Sink
               ]
             })

    %{clock_provider: %{clock: original_clock, provider: :sink}} = :sys.get_state(pipeline)

    Testing.Pipeline.play(pipeline)

    for _ <- 1..tries do
      send(original_clock, {:membrane_clock_update, reported_interval})
      Process.sleep(actual_report_interval)
    end

    Testing.Pipeline.stop(pipeline)

    ticks_amount = receive_ticks(pipeline)

    actual_test_time = tries * actual_report_interval
    expected_ratio = 3.0
    actual_tick_time = actual_test_time / ticks_amount

    assert_in_delta actual_tick_time / tick_interval, expected_ratio, ratio_error
  end

  defp receive_ticks(pipeline, amount \\ 0) do
    receive do
      :tick -> receive_ticks(pipeline, amount + 1)
    after
      @timeout -> amount
    end
  end

  test "synchronize sinks" do
    spec = Membrane.Support.Sync.Pipeline.default_spec()

    options = %Testing.Pipeline.Options{
      module: Membrane.Support.Sync.Pipeline,
      custom_args: spec
    }

    {:ok, pipeline} = Testing.Pipeline.start_link(options)
    :ok = Testing.Pipeline.play(pipeline)

    assert_start_of_stream(pipeline, :sink_a)
    assert_start_of_stream(pipeline, :sink_b, :input, @sync_error_ms)
  end

  test "synchronize dynamically spawned elements" do
    spec = Membrane.Support.Sync.Pipeline.default_spec()
    spec = %{spec | stream_sync: [[:sink_a, :sink_b]]}

    options = %Testing.Pipeline.Options{
      module: Membrane.Support.Sync.Pipeline,
      custom_args: %Membrane.Spec{}
    }

    {:ok, pipeline} = Testing.Pipeline.start_link(options)
    :ok = Testing.Pipeline.play(pipeline)

    assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)
    send(pipeline, {:spawn_children, spec})

    assert_start_of_stream(pipeline, :sink_a)
    assert_start_of_stream(pipeline, :sink_b, :input, @sync_error_ms)
  end

  test "synchronize selected groups" do
    spec = Membrane.Support.Sync.Pipeline.default_spec()

    options = %Testing.Pipeline.Options{
      module: Membrane.Support.Sync.Pipeline,
      custom_args: %{spec | stream_sync: [[:sink_a, :sink_b]]}
    }

    {:ok, pipeline} = Testing.Pipeline.start_link(options)
    :ok = Testing.Pipeline.play(pipeline)

    assert_start_of_stream(pipeline, :sink_a)
    assert_start_of_stream(pipeline, :sink_b, :input, @sync_error_ms)
  end

  defmodule SimpleBin do
    use Membrane.Bin

    def_input_pad :input, demand_unit: :buffers, caps: :any
    def_output_pad :output, caps: :any, demand_unit: :buffers

    @impl true
    def handle_init(_) do
      children = [filter1: TestFilter, filter2: TestFilter]

      spec = %Membrane.Spec{
        children: children,
        links: %{},
        stream_sync: []
      }

      {{:ok, spec: spec}, :ignored}
    end
  end

  test "synchronize selected groups with bin results with error" do
    alias Membrane.Testing.Source

    children = [
      el1: Source,
      el2: SimpleBin
    ]

    links = %{}

    spec = %Membrane.Spec{
      children: children,
      links: links,
      stream_sync: [[:el1, :el2]]
    }

    options = %Testing.Pipeline.Options{
      module: Membrane.Support.Sync.Pipeline,
      custom_args: %{spec | stream_sync: [[:el1, :el2]]}
    }

    assert {:error, reason} = Testing.Pipeline.start_link(options)

    assert {%Membrane.ParentError{}, _} = reason
  end

  test "synchronization inside a bin is possible" do
    {:ok, pipeline} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{elements: [bin: Sync.SyncBin]})

    :ok = Testing.Pipeline.play(pipeline)

    assert_pipeline_notified(pipeline, :bin, {:start_of_stream, :sink_a})
    assert_pipeline_notified(pipeline, :bin, {:start_of_stream, :sink_b}, @sync_error_ms)
  end
end
