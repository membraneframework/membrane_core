defmodule Membrane.Integration.DemandsStarvationTest do
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Testing.{Pipeline, Source}

  defmodule FileLikeFilter do
    @moduledoc false
    # This filter behaves like a file reader: it satisfies every demand in full after a delay,
    # it never redemands and it never demands input. The sink refills its queue in chunks of at
    # least half its size, so the demand is positive again right after each delivery and core
    # re-enters handle_demand without any message in between. The filter reports the number of
    # handle_demand calls with each :pong.
    use Membrane.Filter

    def_input_pad :input, flow_control: :manual, demand_unit: :buffers, accepted_format: _any
    def_output_pad :output, flow_control: :manual, accepted_format: _any

    def_options sleep_time: [spec: non_neg_integer()]

    @impl true
    def handle_init(_ctx, opts), do: {[], %{sleep_time: opts.sleep_time, demands: 0}}

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %Membrane.RemoteStream{}}, demand: {:input, 10}], state}
    end

    @impl true
    def handle_stream_format(:input, _stream_format, _ctx, state), do: {[], state}

    @impl true
    def handle_demand(:output, size, :buffers, _ctx, state) when size > 0 do
      Process.sleep(state.sleep_time)
      buffers = List.duplicate(%Buffer{payload: <<>>}, size)
      {[buffer: {:output, buffers}], %{state | demands: state.demands + 1}}
    end

    @impl true
    def handle_buffer(:input, _buffer, _ctx, state), do: {[], state}

    @impl true
    def handle_parent_notification(:ping, _ctx, state) do
      {[notify_parent: {:pong, state.demands}], state}
    end
  end

  defmodule CountingSink do
    @moduledoc false
    use Membrane.Sink

    def_input_pad :input, flow_control: :manual, demand_unit: :buffers, accepted_format: _any

    @impl true
    def handle_init(_ctx, _opts), do: {[], %{count: 0}}

    @impl true
    def handle_playing(_ctx, state), do: {[demand: :input], state}

    @impl true
    def handle_buffer(:input, _buffer, _ctx, state) do
      {[demand: :input], %{state | count: state.count + 1}}
    end

    @impl true
    def handle_parent_notification(:report, _ctx, state) do
      {[notify_parent: {:count, state.count}], state}
    end
  end

  defmodule TwoInputsSink do
    @moduledoc false
    use Membrane.Sink

    def_input_pad :auto_input, flow_control: :auto, accepted_format: _any

    def_input_pad :manual_input,
      flow_control: :manual,
      demand_unit: :buffers,
      accepted_format: _any

    def_options sleep_time: [spec: non_neg_integer()]

    @impl true
    def handle_init(_ctx, opts) do
      {[], %{sleep_time: opts.sleep_time, counts: %{auto_input: 0, manual_input: 0}}}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[demand: :manual_input, notify_parent: :playing], state}
    end

    @impl true
    def handle_buffer(pad, _buffer, _ctx, state) do
      Process.sleep(state.sleep_time)
      state = update_in(state, [:counts, pad], &(&1 + 1))
      actions = if pad == :manual_input, do: [demand: :manual_input], else: []
      {actions, state}
    end

    @impl true
    def handle_parent_notification(:report, _ctx, state) do
      {[notify_parent: {:counts, state.counts}], state}
    end
  end

  test "filter satisfying whole demands with a delay keeps answering its parent" do
    spec =
      child(:source, Source)
      |> child(:filter, %FileLikeFilter{sleep_time: 5})
      |> child(:sink, CountingSink)

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    count = await_count_above(pipeline, 0)

    Enum.reduce(1..5, {count, 0}, fn _i, {count, demands} ->
      Pipeline.notify_child(pipeline, :filter, :ping)
      assert_pipeline_notified(pipeline, :filter, {:pong, new_demands}, 1_000)
      assert new_demands > demands

      {await_count_above(pipeline, count), new_demands}
    end)

    Pipeline.terminate(pipeline)
  end

  defp await_count_above(pipeline, previous_count) do
    Pipeline.notify_child(pipeline, :sink, :report)
    assert_pipeline_notified(pipeline, :sink, {:count, count})
    if count > previous_count, do: count, else: await_count_above(pipeline, previous_count)
  end

  test "slow element with an auto and a manual input pad consumes both pads at comparable rates" do
    spam =
      {0,
       fn counter, _size ->
         {[buffer: {:output, %Buffer{payload: <<counter::32>>}}, redemand: :output], counter + 1}
       end}

    spec = [
      child(:auto_source, %Source{output: spam})
      |> via_in(:auto_input)
      |> child(:sink, %TwoInputsSink{sleep_time: 1}),
      child(:manual_source, %Source{output: spam})
      |> via_in(:manual_input)
      |> get_child(:sink)
    ]

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_pipeline_notified(pipeline, :sink, :playing)

    Process.sleep(2_000)
    Pipeline.notify_child(pipeline, :sink, :report)
    assert_pipeline_notified(pipeline, :sink, {:counts, counts})

    %{auto_input: auto, manual_input: manual} = counts

    assert auto + manual > 500
    assert max(auto, manual) <= 4 * min(auto, manual), "uneven consumption: #{inspect(counts)}"

    Pipeline.terminate(pipeline)
  end
end
