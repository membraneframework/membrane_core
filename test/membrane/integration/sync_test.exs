defmodule Membrane.Integration.SyncTest do
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions

  alias Membrane.{Testing, Time}
  alias Membrane.Support.{Sync, TestBins}
  alias TestBins.TestFilter

  @tick_number_error 5
  @sync_error_ms 5

  @tag :long_running
  test "When ratio = 1 amount of lost ticks is roughly the same regardless of the time of transmission" do
    tick_interval = 1

    children = [
      source: %Sync.Source{
        tick_interval: tick_interval |> Time.milliseconds(),
        test_process: self()
      },
      sink: Sync.Sink
    ]

    pipeline_opts = [
      links: Membrane.ParentSpec.link_linear(children)
    ]

    for tries <- [100, 1000, 10_000] do
      assert {:ok, pipeline} = Testing.Pipeline.start_link(pipeline_opts)
      Testing.Pipeline.play(pipeline)

      assert_pipeline_playback_changed(pipeline, :prepared, :playing)
      Process.sleep(tick_interval * tries)

      Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)

      ticks_amount = Sync.Helper.receive_ticks()

      assert_in_delta ticks_amount, tries, @tick_number_error
    end
  end

  test "synchronize sinks" do
    spec = Membrane.Support.Sync.Pipeline.default_spec()

    options = [
      module: Membrane.Support.Sync.Pipeline,
      custom_args: spec
    ]

    {:ok, pipeline} = Testing.Pipeline.start_link(options)
    :ok = Testing.Pipeline.play(pipeline)

    assert_start_of_stream(pipeline, :sink_a)
    assert_start_of_stream(pipeline, :sink_b, :input, @sync_error_ms)
    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
  end

  test "synchronize dynamically spawned elements" do
    spec = Membrane.Support.Sync.Pipeline.default_spec()
    spec = %{spec | stream_sync: [[:sink_a, :sink_b]]}

    options = [
      module: Membrane.Support.Sync.Pipeline,
      custom_args: %Membrane.ParentSpec{}
    ]

    {:ok, pipeline} = Testing.Pipeline.start_link(options)
    :ok = Testing.Pipeline.play(pipeline)

    assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)
    send(pipeline, {:spawn_children, spec})

    assert_start_of_stream(pipeline, :sink_a)
    assert_start_of_stream(pipeline, :sink_b, :input, @sync_error_ms)
    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
  end

  test "synchronize selected groups" do
    spec = Membrane.Support.Sync.Pipeline.default_spec()

    options = [
      module: Membrane.Support.Sync.Pipeline,
      custom_args: %{spec | stream_sync: [[:sink_a, :sink_b]]}
    ]

    {:ok, pipeline} = Testing.Pipeline.start_link(options)
    :ok = Testing.Pipeline.play(pipeline)

    assert_start_of_stream(pipeline, :sink_a)
    assert_start_of_stream(pipeline, :sink_b, :input, @sync_error_ms)
    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
  end

  defmodule SimpleBin do
    use Membrane.Bin

    def_input_pad :input, demand_unit: :buffers, caps: :any
    def_output_pad :output, caps: :any, demand_unit: :buffers

    @impl true
    def handle_init(_options) do
      children = [filter1: TestFilter, filter2: TestFilter]

      spec = %Membrane.ParentSpec{
        children: children,
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

    spec = %Membrane.ParentSpec{
      children: children,
      stream_sync: [[:el1, :el2]]
    }

    options = [
      module: Membrane.Support.Sync.Pipeline,
      custom_args: %{spec | stream_sync: [[:el1, :el2]]}
    ]

    assert {:error, reason} = Testing.Pipeline.start_link(options)

    assert {%Membrane.ParentError{}, _} = reason
  end

  test "synchronization inside a bin is possible" do
    children = [bin: Sync.SyncBin]

    {:ok, pipeline} = Testing.Pipeline.start_link(children: children)

    :ok = Testing.Pipeline.play(pipeline)

    assert_pipeline_notified(pipeline, :bin, {:start_of_stream, :sink_a})
    assert_pipeline_notified(pipeline, :bin, {:start_of_stream, :sink_b}, @sync_error_ms)
  end
end
