defmodule Membrane.Integration.SyncTest do
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.{Testing, Time}
  alias Membrane.Support.{Sync, TestBins}
  alias TestBins.TestFilter

  @tick_number_error 5
  @sync_error_ms 5

  @tag :long_running
  test "When ratio = 1 amount of lost ticks is roughly the same regardless of the time of transmission" do
    tick_interval = 1

    links = [
      child(:source, %Sync.Source{
        tick_interval: tick_interval |> Time.milliseconds(),
        test_process: self()
      })
      |> child(:sink, Sync.Sink)
    ]

    pipeline_opts = [
      spec: links
    ]

    for tries <- [100, 1000, 10_000] do
      pipeline = Testing.Pipeline.start_link_supervised!(pipeline_opts)
      assert_pipeline_notified(pipeline, :source, :start_timer)
      Process.sleep(tick_interval * tries)
      Testing.Pipeline.terminate(pipeline)
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

    pipeline = Testing.Pipeline.start_link_supervised!(options)

    assert_start_of_stream(pipeline, :sink_a)
    assert_start_of_stream(pipeline, :sink_b, :input, @sync_error_ms)
  end

  test "synchronize dynamically spawned elements" do
    {spec, spec_options} = Membrane.Support.Sync.Pipeline.default_spec()
    spec = {spec, Keyword.put(spec_options, :stream_sync, [[:sink_a, :sink_b]])}

    options = [
      module: Membrane.Support.Sync.Pipeline,
      custom_args: []
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(options)

    send(pipeline, {:spawn_children, spec})

    assert_start_of_stream(pipeline, :sink_a)
    assert_start_of_stream(pipeline, :sink_b, :input, @sync_error_ms)
  end

  test "synchronize selected groups" do
    {spec, spec_options} = Membrane.Support.Sync.Pipeline.default_spec()
    spec = {spec, Keyword.put(spec_options, :stream_sync, [[:sink_a, :sink_b]])}

    options = [
      module: Membrane.Support.Sync.Pipeline,
      custom_args: spec
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(options)

    assert_start_of_stream(pipeline, :sink_a)
    assert_start_of_stream(pipeline, :sink_b, :input, @sync_error_ms)
  end

  defmodule SimpleBin do
    use Membrane.Bin

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any

    @impl true
    def handle_init(_ctx, _options) do
      children = [child(:filter1, TestFilter), child(:filter2, TestFilter)]

      spec = {
        children,
        stream_sync: []
      }

      {[spec: spec], :ignored}
    end
  end

  test "synchronize selected groups with bin results with error" do
    alias Membrane.Testing.Source

    children = [
      child(:el1, Source),
      child(:el2, SimpleBin)
    ]

    spec = {
      children,
      stream_sync: [[:el1, :el2]]
    }

    options = [
      module: Membrane.Support.Sync.Pipeline,
      custom_args: spec
    ]

    assert {:error, reason} = Testing.Pipeline.start_link_supervised(options)

    assert {%Membrane.ParentError{}, _} = reason
  end

  test "synchronization inside a bin is possible" do
    children = [child(:bin, Sync.SyncBin)]

    pipeline = Testing.Pipeline.start_link_supervised!(spec: children)

    assert_pipeline_notified(pipeline, :bin, {:start_of_stream, :sink_a})
    assert_pipeline_notified(pipeline, :bin, {:start_of_stream, :sink_b}, @sync_error_ms)
  end
end
