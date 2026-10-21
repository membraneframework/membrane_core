defmodule Membrane.Integration.DemandsTest do
  use Bunch
  use ExUnit.Case, async: true

  import ExUnit.Assertions
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Support.DemandsTest.Filter
  alias Membrane.Testing
  alias Membrane.Testing.{Pipeline, Sink, Source}

  require Membrane.Pad, as: Pad

  defp assert_buffers_received(range, pipeline, filters_count \\ 1) do
    suffix = String.duplicate(<<255>>, filters_count)

    Enum.each(range, fn i ->
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: <<^i::16, ^suffix::binary>>})
    end)
  end

  defp test_pipeline(pid) do
    assert_sink_playing(pid, :sink)

    demand = 500
    Pipeline.notify_child(pid, :sink, {:make_demand, demand})

    0..(demand - 1)
    |> assert_buffers_received(pid)

    pattern = %Buffer{payload: <<demand::16>> <> <<255>>}
    refute_sink_buffer(pid, :sink, ^pattern, 0)
    Pipeline.notify_child(pid, :sink, {:make_demand, demand})

    demand..(2 * demand - 1)
    |> assert_buffers_received(pid)
  end

  test "Regular pipeline with proper demands" do
    links =
      child(:source, Source)
      |> child(:filter, Filter)
      |> child(:sink, %Sink{autodemand: false})

    pid = Pipeline.start_link_supervised!(spec: links)
    test_pipeline(pid)
    Pipeline.terminate(pid)
  end

  test "Pipeline with filter underestimating demand" do
    filter_demand_gen = fn _incoming_demand -> 2 end

    links =
      child(:source, Source)
      |> child(:filter, %Filter{demand_generator: filter_demand_gen})
      |> child(:sink, %Sink{autodemand: false})

    pid = Pipeline.start_link_supervised!(spec: links)
    test_pipeline(pid)
    Pipeline.terminate(pid)
  end

  test "Pipeline with source not generating enough buffers" do
    alias Membrane.Buffer

    actions_gen = fn cnt, _size ->
      cnt..(4 + cnt - 1)
      |> Enum.map(fn cnt ->
        buf = %Buffer{payload: <<cnt::16>>}

        {:buffer, {:output, buf}}
      end)
      |> Enum.concat(redemand: :output)
      ~> {&1, cnt + 4}
    end

    spec =
      child(:source, %Source{output: {0, actions_gen}})
      |> child(:filter, Filter)
      |> child(:sink, %Sink{autodemand: false})

    pid = Pipeline.start_link_supervised!(spec: spec)
    test_pipeline(pid)
    Pipeline.terminate(pid)
  end

  test "handle_demand is not called for pad with end of stream" do
    defmodule Source do
      use Membrane.Source

      defmodule StreamFormat do
        defstruct []
      end

      def_output_pad :output, flow_control: :manual, accepted_format: _any

      @impl true
      def handle_init(_ctx, _opts), do: {[], %{eos_sent?: false}}

      @impl true
      def handle_demand(_pad, _size, _unit, _ctx, %{eos_sent?: true}) do
        raise "handle_demand cannot be called after sending end of stream"
      end

      @impl true
      def handle_demand(:output, n, :buffers, _ctx, %{eos_sent?: false} = state) do
        buffers =
          1..(n - 1)//1
          |> Enum.map(fn _i -> %Membrane.Buffer{payload: <<>>} end)

        Process.send_after(self(), :second_left, 1000)

        {[stream_format: {:output, %StreamFormat{}}, buffer: {:output, buffers}], state}
      end

      @impl true
      def handle_info(:second_left, _ctx, %{eos_sent?: false} = state) do
        buffer = %Membrane.Buffer{payload: <<>>}
        state = %{state | eos_sent?: true}

        {[buffer: {:output, buffer}, end_of_stream: :output], state}
      end
    end

    defmodule Sink do
      use Membrane.Sink

      def_input_pad :input, flow_control: :manual, demand_unit: :buffers, accepted_format: _any

      @impl true
      def handle_playing(_ctx, state), do: {[demand: {:input, 1}], state}

      @impl true
      def handle_buffer(:input, _buffer, _ctx, state), do: {[demand: {:input, 1}], state}
    end

    pipeline = Testing.Pipeline.start_link_supervised!(spec: child(Source) |> child(:sink, Sink))

    assert_end_of_stream(pipeline, :sink)

    Testing.Pipeline.terminate(pipeline)
  end

  defmodule RedemandingSource do
    use Membrane.Source

    @sleep_time 10

    def_output_pad :output, accepted_format: _any, flow_control: :manual

    defmodule StreamFormat do
      defstruct []
    end

    @spec sleep_time() :: pos_integer()
    def sleep_time(), do: @sleep_time

    @impl true
    def handle_playing(_ctx, _default_state) do
      {[stream_format: {:output, %StreamFormat{}}], %{counter: 0}}
    end

    @impl true
    def handle_demand(:output, _size, _unit, _ctx, state) do
      Process.sleep(@sleep_time)

      actions = [buffer: {:output, %Membrane.Buffer{payload: state.counter}}, redemand: :output]
      {actions, Map.update!(state, :counter, &(&1 + 1))}
    end
  end

  defmodule PausingSink do
    use Membrane.Sink

    def_input_pad :input, accepted_format: _any, flow_control: :auto

    @impl true
    def handle_init(_ctx, _opts), do: {[], %{counter: 0}}

    @impl true
    def handle_playing(_ctx, state) do
      {[notify_parent: :playing], state}
    end

    @impl true
    def handle_buffer(:input, _buffer, _ctx, state) do
      {[], Map.update!(state, :counter, &(&1 + 1))}
    end

    @impl true
    def handle_parent_notification(action, _ctx, state)
        when action in [:pause_auto_demand, :resume_auto_demand] do
      actions = [
        {action, :input},
        notify_parent: {:buff_no, state.counter}
      ]

      {actions, %{state | counter: 0}}
    end
  end

  defmodule Funnel do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any, flow_control: :auto, availability: :on_request
    def_output_pad :output, accepted_format: _any, flow_control: :auto

    def_options pads_upperbounds: [spec: map()]

    @impl true
    def handle_init(_ctx, %{pads_upperbounds: pads_upperbounds}) do
      {[], %{pads_upperbounds: pads_upperbounds, pads_counters: %{}}}
    end

    @impl true
    def handle_pad_added(pad, _ctx, state) do
      {[], put_in(state, [:pads_counters, pad], 0)}
    end

    @impl true
    def handle_buffer(pad, buffer, ctx, state) do
      buffer = %{buffer | metadata: pad}

      {pad_counter, state} = get_and_update_in(state, [:pads_counters, pad], &{&1, &1 + 1})

      actions =
        with {:ok, upperbound} when pad_counter > upperbound <-
               Map.fetch(state.pads_upperbounds, pad),
             %{auto_demand_paused?: false} <- ctx.pads[pad] do
          [pause_auto_demand: pad, buffer: {:output, buffer}]
        else
          _other -> [buffer: {:output, buffer}]
        end

      {actions, state}
    end

    @impl true
    def handle_end_of_stream(_pad, ctx, state) do
      if ctx.pads.output.end_of_stream? do
        {[], state}
      else
        {[end_of_stream: :output], state}
      end
    end
  end

  test "funnel pausing auto demands on one of its pads" do
    spec = [
      child({:source, :a}, RedemandingSource)
      |> via_in(Pad.ref(:input, :a), auto_demand_size: 10)
      |> child(:funnel, %Funnel{pads_upperbounds: %{Pad.ref(:input, :a) => 100}})
      |> child(:sink, %Testing.Sink{autodemand: true}),
      child({:source, :b}, RedemandingSource)
      |> via_in(Pad.ref(:input, :b), auto_demand_size: 10)
      |> get_child(:funnel)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    assert_sink_buffer(pipeline, :sink, %{payload: 100, metadata: Pad.ref(:input, :a)})
    assert_sink_buffer(pipeline, :sink, %{payload: 100, metadata: Pad.ref(:input, :b)})
    assert_sink_buffer(pipeline, :sink, %{payload: 500, metadata: Pad.ref(:input, :b)}, 8000)
    refute_sink_buffer(pipeline, :sink, %{payload: 200, metadata: Pad.ref(:input, :a)}, 5000)

    Testing.Pipeline.terminate(pipeline)
  end

  defmodule Sync do
    use Bunch
    use ExUnit.Case, async: false

    alias Membrane.Integration.DemandsTest.{PausingSink, RedemandingSource}

    test "actions :pause_auto_demand and :resume_auto_demand" do
      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(RedemandingSource)
            |> via_in(:input, auto_demand_size: 10)
            |> child(:sink, PausingSink)
        )

      assert_sink_playing(pipeline, :sink)

      for i <- 1..10 do
        # during sleep below source should send around 100 buffers
        Process.sleep(100 * RedemandingSource.sleep_time())

        Testing.Pipeline.execute_actions(pipeline, notify_child: {:sink, :pause_auto_demand})

        assert_pipeline_notified(pipeline, :sink, {:buff_no, buff_no})
        # sink should receive around 100 buffers, but the boundary is set to 65, in case of eg.
        # slowdown of the source when running all tests in the project asynchronously
        if i != 1, do: assert(buff_no > 65)

        # during sleep below source should send up to about auto_demand_size = 10 buffers
        Process.sleep(100 * RedemandingSource.sleep_time())

        Testing.Pipeline.execute_actions(pipeline, notify_child: {:sink, :resume_auto_demand})

        assert_pipeline_notified(pipeline, :sink, {:buff_no, buff_no})
        # sink should probably receive between 5 and 15 buffers, but the boundary is set to 25,
        # to handle the case when eg. there is a delay in receiving the notification from the
        # pipeline by the :sink
        assert buff_no < 25
      end

      Testing.Pipeline.terminate(pipeline)
    end
  end

  @timestamp_demand_units_with_sink_names [
    {:timestamp, Sink.Timestamp},
    {{:timestamp, :pts}, Sink.Timestamp.PTS},
    {{:timestamp, :dts}, Sink.Timestamp.DTS},
    {{:timestamp, :dts_or_pts}, Sink.Timestamp.DTSorPTS}
  ]

  @other_demand_units_with_sink_names [
    {:buffers, Sink.Buffers},
    {:bytes, Sink.Bytes}
  ]

  for {demand_unit, sink_name} <-
        @timestamp_demand_units_with_sink_names ++ @other_demand_units_with_sink_names do
    defmodule sink_name do
      use Membrane.Sink

      def_input_pad :input,
        accepted_format: _any,
        flow_control: :manual,
        demand_unit: demand_unit

      @impl true
      def handle_playing(_ctx, state), do: {[notify_parent: :playing], state}

      @impl true
      def handle_buffer(:input, buffer, _ctx, state) do
        {[notify_parent: {:buffer, buffer}], state}
      end

      @impl true
      def handle_event(:input, event, _ctx, state) do
        {[notify_parent: {:event, event}], state}
      end

      @impl true
      def handle_stream_format(:input, stream_format, _ctx, state) do
        {[notify_parent: {:stream_format, stream_format}], state}
      end

      @impl true
      def handle_end_of_stream(:input, _ctx, state) do
        {[notify_parent: :end_of_stream], state}
      end

      @impl true
      def handle_parent_notification({:make_demand, value}, _ctx, state) do
        {[demand: {:input, value}], state}
      end
    end
  end

  @timestamp_offsets [0, 5, 1421, -9329]

  for {demand_unit, sink_name} <- @timestamp_demand_units_with_sink_names,
      timestamp_offset <- @timestamp_offsets do
    test "demands with demand unit set to #{inspect(demand_unit)} and timestamp offset #{timestamp_offset}" do
      timestamp_offset = unquote(timestamp_offset)

      buffers =
        0..100
        |> Enum.map(fn i -> buffer(i, timestamp_offset) end)

      spec =
        child(:source, %Testing.Source{output: buffers})
        |> child(:sink, unquote(sink_name))

      pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

      assert_pipeline_notified(pipeline, :sink, :playing)

      [
        {0, [0]},
        {1, [1]},
        {11, [2]},
        {271, 3..28},
        {277, []},
        {341, 29..35},
        {460, 36..46},
        {461, [47]},
        {571, 48..58},
        {680, 59..68},
        {791, 69..80},
        {901, 81..91},
        {1012, 92..100}
      ]
      |> Enum.each(fn {demand_value, expected_buffers} ->
        refute_pipeline_notified(pipeline, :sink, {:buffer, _buffer}, 100)

        Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, demand_value})

        expected_buffers
        |> Enum.each(fn i ->
          _timestamp = timestamp(i, timestamp_offset)
          _payload = inspect(i)

          assert_pipeline_notified(pipeline, :sink, {:buffer, buffer})
          assert buffer == buffer(i, timestamp_offset)
        end)

        refute_pipeline_notified(pipeline, :sink, {:buffer, _buffer}, 100)
      end)

      assert_end_of_stream(pipeline, :sink)
      Testing.Pipeline.terminate(pipeline)
    end
  end

  defp buffer(idx, timestamp_offset) do
    %Membrane.Buffer{
      payload: inspect(idx),
      pts: timestamp(idx, timestamp_offset),
      dts: timestamp(idx, timestamp_offset)
    }
  end

  defp timestamp(buffer_idx, offset), do: 10 * buffer_idx + offset

  defmodule ReportingSource do
    use Membrane.Source

    def_output_pad :output, flow_control: :manual, accepted_format: _any

    def_options surplus: [spec: non_neg_integer(), default: 0]

    @impl true
    def handle_init(_ctx, opts), do: {[], %{surplus: opts.surplus, produced: 0}}

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %Membrane.RemoteStream{}}], state}
    end

    @impl true
    def handle_demand(:output, size, :buffers, _ctx, state) do
      first = state.produced + 1
      last = state.produced + size + state.surplus
      buffers = Enum.map(first..last//1, &%Buffer{payload: <<&1::16>>})

      actions = [
        buffer: {:output, buffers},
        notify_parent: {:handle_demand, size, last},
        redemand: :output
      ]

      {actions, %{state | produced: last}}
    end
  end

  defmodule OneBufferPerDemandSource do
    use Membrane.Source

    def_output_pad :output, flow_control: :manual, accepted_format: _any

    def_options buffers_count: [spec: pos_integer()]

    @impl true
    def handle_init(_ctx, opts), do: {[], Map.put(Map.from_struct(opts), :counter, 0)}

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %Membrane.RemoteStream{}}], state}
    end

    @impl true
    def handle_demand(
          :output,
          _size,
          :buffers,
          _ctx,
          %{counter: count, buffers_count: count} = state
        ) do
      {[end_of_stream: :output], state}
    end

    @impl true
    def handle_demand(:output, _size, :buffers, _ctx, state) do
      counter = state.counter + 1

      {[buffer: {:output, %Buffer{payload: counter}}, redemand: :output],
       %{state | counter: counter}}
    end
  end

  defmodule TenByteBuffersSource do
    use Membrane.Source

    def_output_pad :output, flow_control: :manual, accepted_format: _any, demand_unit: :buffers

    @impl true
    def handle_init(_ctx, _opts), do: {[], %{produced: 0}}

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %Membrane.RemoteStream{}}], state}
    end

    @impl true
    def handle_demand(:output, size, :buffers, _ctx, state) do
      first = state.produced + 1
      last = state.produced + size
      buffers = Enum.map(first..last//1, &%Buffer{payload: payload(&1)})
      {[buffer: {:output, buffers}], %{state | produced: last}}
    end

    @spec payload(non_neg_integer()) :: binary()
    def payload(i), do: <<i::40, 0::40>>
  end

  defmodule ActionsSource do
    use Membrane.Source

    def_output_pad :output, flow_control: :manual, accepted_format: _any

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %Membrane.RemoteStream{}}], state}
    end

    @impl true
    def handle_demand(:output, _size, :buffers, _ctx, state), do: {[], state}

    @impl true
    def handle_parent_notification({:execute_actions, actions}, _ctx, state), do: {actions, state}
  end

  defmodule RedemandingOnEndOfStreamSource do
    use Membrane.Source

    def_output_pad :output, flow_control: :manual, accepted_format: _any

    @impl true
    def handle_init(_ctx, _opts), do: {[], %{eos_sent?: false}}

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %Membrane.RemoteStream{}}], state}
    end

    @impl true
    def handle_demand(:output, _size, :buffers, _ctx, %{eos_sent?: true}) do
      raise "handle_demand cannot be called after sending end of stream"
    end

    @impl true
    def handle_demand(:output, _size, :buffers, _ctx, state) do
      actions = [
        buffer: {:output, %Buffer{payload: 1}},
        end_of_stream: :output,
        redemand: :output
      ]

      {actions, %{state | eos_sent?: true}}
    end
  end

  defmodule DemandingOnEndOfStreamSink do
    use Membrane.Sink

    def_input_pad :input, accepted_format: _any, flow_control: :manual, demand_unit: :buffers

    @impl true
    def handle_playing(_ctx, state), do: {[notify_parent: :playing], state}

    @impl true
    def handle_buffer(:input, buffer, _ctx, state),
      do: {[notify_parent: {:buffer, buffer}], state}

    @impl true
    def handle_end_of_stream(:input, _ctx, state) do
      {[demand: {:input, 5}, notify_parent: :end_of_stream], state}
    end

    @impl true
    def handle_parent_notification({:make_demand, size}, _ctx, state) do
      {[demand: {:input, size}], state}
    end

    @impl true
    def handle_parent_notification(:ping, _ctx, state), do: {[notify_parent: :pong], state}
  end

  defmodule SecondStreamFormat do
    defstruct []
  end

  test "many single-buffer demands deliver exactly one buffer each" do
    spec =
      child(:source, Source)
      |> child(:filter, Filter)
      |> child(:sink, %Sink{autodemand: false})

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_sink_playing(pipeline, :sink)

    single_demands = 50

    for i <- 0..(single_demands - 1) do
      Pipeline.notify_child(pipeline, :sink, {:make_demand, 1})
      assert_buffers_received(i..i, pipeline)
      next = i + 1
      refute_sink_buffer(pipeline, :sink, %Buffer{payload: <<^next::16, 255>>}, 0)
    end

    batch_demand = 200
    Pipeline.notify_child(pipeline, :sink, {:make_demand, batch_demand})
    assert_buffers_received(single_demands..(single_demands + batch_demand - 1), pipeline)
    refute_sink_buffer(pipeline, :sink, _, 100)

    Pipeline.terminate(pipeline)
  end

  test "end of stream waits until all buffers preceding it are demanded" do
    payloads = Enum.to_list(1..30)

    spec =
      child(:source, %Source{output: payloads})
      |> child(:sink, %Sink{autodemand: false})

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_sink_playing(pipeline, :sink)

    [{10, 1..10}, {10, 11..20}, {1000, 21..30}]
    |> Enum.each(fn {demand, expected_payloads} ->
      refute_end_of_stream(pipeline, :sink, 100)
      Pipeline.notify_child(pipeline, :sink, {:make_demand, demand})
      assert_payloads_received(expected_payloads, pipeline)
    end)

    assert_end_of_stream(pipeline, :sink)
    refute_sink_buffer(pipeline, :sink, _, 100)

    Pipeline.terminate(pipeline)
  end

  test "manual input queues with small target sizes bound the production of the source" do
    target_queue_size = 10
    filters_count = 3
    queues_count = filters_count + 1
    min_demand = div(target_queue_size, 2)
    max_queue_fill = target_queue_size - 1 + min_demand
    production_upper_bound = queues_count * max_queue_fill
    production_lower_bound = queues_count * target_queue_size

    spec =
      child(:source, ReportingSource)
      |> via_in(:input, target_queue_size: target_queue_size)
      |> child(:filter1, Filter)
      |> via_in(:input, target_queue_size: target_queue_size)
      |> child(:filter2, Filter)
      |> via_in(:input, target_queue_size: target_queue_size)
      |> child(:filter3, Filter)
      |> via_in(:input, target_queue_size: target_queue_size)
      |> child(:sink, %Sink{autodemand: false})

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_sink_playing(pipeline, :sink)

    produced = await_settled_production(pipeline)
    assert produced in production_lower_bound..production_upper_bound
    refute_sink_buffer(pipeline, :sink, _, 0)

    demand = 100
    Pipeline.notify_child(pipeline, :sink, {:make_demand, demand})
    assert_buffers_received(1..demand, pipeline, filters_count)

    produced = await_settled_production(pipeline, produced)
    assert produced in (demand + production_lower_bound)..(demand + production_upper_bound)
    refute_sink_buffer(pipeline, :sink, _, 0)

    Pipeline.terminate(pipeline)
  end

  test "demands in bytes split buffers across demands" do
    target_queue_size = 4

    spec =
      child(:source, TenByteBuffersSource)
      |> via_in(:input, target_queue_size: target_queue_size)
      |> child(:sink, Sink.Bytes)

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_pipeline_notified(pipeline, :sink, :playing)

    <<payload_3_head::binary-size(5), payload_3_tail::binary-size(5)>> =
      TenByteBuffersSource.payload(3)

    <<payload_14_head::binary-size(5), _payload_14_tail::binary-size(5)>> =
      TenByteBuffersSource.payload(14)

    [
      {25, [TenByteBuffersSource.payload(1), TenByteBuffersSource.payload(2), payload_3_head]},
      {35, [payload_3_tail | Enum.map(4..6, &TenByteBuffersSource.payload/1)]},
      {60, Enum.map(7..12, &TenByteBuffersSource.payload/1)},
      {15, [TenByteBuffersSource.payload(13), payload_14_head]}
    ]
    |> Enum.each(fn {demand_bytes, expected_payloads} ->
      Pipeline.notify_child(pipeline, :sink, {:make_demand, demand_bytes})

      Enum.each(expected_payloads, fn payload ->
        assert_pipeline_notified(pipeline, :sink, {:buffer, %Buffer{payload: ^payload}})
      end)

      refute_pipeline_notified(pipeline, :sink, {:buffer, _buffer}, 100)
    end)

    Pipeline.terminate(pipeline)
  end

  test "demand altering function changes the pending demand" do
    spec =
      child(:source, Source)
      |> child(:sink, Sink.Buffers)

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_pipeline_notified(pipeline, :sink, :playing)

    [
      {2, 0..1},
      {&(&1 + 3), 2..4},
      {fn _pending_demand -> 0 end, []},
      {&(&1 + 1), [5]}
    ]
    |> Enum.each(fn {demand, expected_range} ->
      Pipeline.notify_child(pipeline, :sink, {:make_demand, demand})

      Enum.each(expected_range, fn i ->
        assert_pipeline_notified(pipeline, :sink, {:buffer, %Buffer{payload: <<^i::16>>}})
      end)

      refute_pipeline_notified(pipeline, :sink, {:buffer, _buffer}, 100)
    end)

    Pipeline.terminate(pipeline)
  end

  test "source redemanding after every single buffer delivers the whole stream" do
    buffers_count = 3000

    spec =
      child(:source, %OneBufferPerDemandSource{buffers_count: buffers_count})
      |> child(:sink, Sink)

    pipeline = Pipeline.start_link_supervised!(spec: spec)

    assert_payloads_received(1..buffers_count, pipeline)
    assert_end_of_stream(pipeline, :sink)

    Pipeline.terminate(pipeline)
  end

  test "handle_demand is not called while the demand is overestimated" do
    target_queue_size = 20
    surplus = 5
    demand = 10

    spec =
      child(:source, %ReportingSource{surplus: surplus})
      |> via_in(:input, target_queue_size: target_queue_size)
      |> child(:sink, %Sink{autodemand: false})

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_sink_playing(pipeline, :sink)

    assert_pipeline_notified(pipeline, :source, {:handle_demand, ^target_queue_size, produced})
    assert produced == target_queue_size + surplus
    refute_pipeline_notified(pipeline, :source, {:handle_demand, _size, _produced}, 300)

    Pipeline.notify_child(pipeline, :sink, {:make_demand, demand})
    assert_buffers_received(1..demand, pipeline, 0)

    expected_size = demand - surplus
    assert_pipeline_notified(pipeline, :source, {:handle_demand, ^expected_size, produced})
    assert produced == target_queue_size + surplus + demand
    refute_pipeline_notified(pipeline, :source, {:handle_demand, _size, _produced}, 300)

    Pipeline.terminate(pipeline)
  end

  test "manual input queue tops up by at least half of its target size" do
    target_queue_size = 10
    min_top_up = div(target_queue_size, 2)
    demands = [1, 7, 9]

    spec =
      child(:source, ReportingSource)
      |> via_in(:input, target_queue_size: target_queue_size)
      |> child(:sink, %Sink{autodemand: false})

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_sink_playing(pipeline, :sink)

    assert_pipeline_notified(
      pipeline,
      :source,
      {:handle_demand, ^target_queue_size, ^target_queue_size}
    )

    refute_pipeline_notified(pipeline, :source, {:handle_demand, _size, _produced}, 300)

    Enum.reduce(demands, {1, target_queue_size, target_queue_size}, fn demand,
                                                                       {next_payload, queue_size,
                                                                        produced} ->
      Pipeline.notify_child(pipeline, :sink, {:make_demand, demand})
      assert_buffers_received(next_payload..(next_payload + demand - 1), pipeline, 0)

      queue_size = queue_size - demand
      top_up = max(target_queue_size - queue_size, min_top_up)
      produced = produced + top_up
      assert_pipeline_notified(pipeline, :source, {:handle_demand, ^top_up, ^produced})
      refute_pipeline_notified(pipeline, :source, {:handle_demand, _size, _produced}, 300)

      {next_payload + demand, queue_size + top_up, produced}
    end)

    Pipeline.terminate(pipeline)
  end

  test "redemand returned along with end of stream does not call handle_demand again" do
    spec =
      child(:source, RedemandingOnEndOfStreamSource)
      |> child(:sink, Sink)

    pipeline = Pipeline.start_link_supervised!(spec: spec)

    assert_sink_buffer(pipeline, :sink, %Buffer{payload: 1})
    assert_end_of_stream(pipeline, :sink)
    assert Process.alive?(Pipeline.get_child_pid!(pipeline, :source))

    Pipeline.terminate(pipeline)
  end

  test "events and stream formats keep their order in the manual input queue" do
    spec =
      child(:source, ActionsSource)
      |> child(:sink, Sink.Buffers)

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_pipeline_notified(pipeline, :sink, :playing)
    assert_next_sink_notification(pipeline, {:stream_format, %Membrane.RemoteStream{}})

    actions = [
      buffer: {:output, %Buffer{payload: 1}},
      buffer: {:output, %Buffer{payload: 2}},
      event: {:output, %Membrane.Event.Discontinuity{duration: 1}},
      stream_format: {:output, %SecondStreamFormat{}},
      buffer: {:output, %Buffer{payload: 3}},
      event: {:output, %Membrane.Event.Discontinuity{duration: 2}},
      end_of_stream: :output
    ]

    Pipeline.notify_child(pipeline, :source, {:execute_actions, actions})
    refute_pipeline_notified(pipeline, :sink, _notification, 100)

    Pipeline.notify_child(pipeline, :sink, {:make_demand, 2})
    assert_next_sink_notification(pipeline, {:buffer, %Buffer{payload: 1}})
    assert_next_sink_notification(pipeline, {:buffer, %Buffer{payload: 2}})
    assert_next_sink_notification(pipeline, {:event, %Membrane.Event.Discontinuity{duration: 1}})
    assert_next_sink_notification(pipeline, {:stream_format, %SecondStreamFormat{}})
    refute_pipeline_notified(pipeline, :sink, _notification, 100)

    Pipeline.notify_child(pipeline, :sink, {:make_demand, 1})
    assert_next_sink_notification(pipeline, {:buffer, %Buffer{payload: 3}})
    assert_next_sink_notification(pipeline, {:event, %Membrane.Event.Discontinuity{duration: 2}})
    assert_next_sink_notification(pipeline, :end_of_stream)
    assert_end_of_stream(pipeline, :sink)

    Pipeline.terminate(pipeline)
  end

  test "demand returned from handle_end_of_stream does not crash the element" do
    payloads = Enum.to_list(1..10)

    spec =
      child(:source, %Source{output: payloads})
      |> child(:sink, DemandingOnEndOfStreamSink)

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_pipeline_notified(pipeline, :sink, :playing)

    Pipeline.notify_child(pipeline, :sink, {:make_demand, 20})

    Enum.each(payloads, fn i ->
      assert_pipeline_notified(pipeline, :sink, {:buffer, %Buffer{payload: ^i}})
    end)

    assert_pipeline_notified(pipeline, :sink, :end_of_stream)
    assert_end_of_stream(pipeline, :sink)

    Pipeline.notify_child(pipeline, :sink, :ping)
    assert_pipeline_notified(pipeline, :sink, :pong)

    Pipeline.terminate(pipeline)
  end

  defp assert_payloads_received(payloads, pipeline) do
    Enum.each(payloads, fn i ->
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: ^i})
    end)
  end

  defp assert_next_sink_notification(pipeline, expected_notification) do
    assert_receive {Pipeline, ^pipeline, {:handle_child_notification, {notification, :sink}}}
    assert notification == expected_notification
  end

  defp await_settled_production(pipeline) do
    assert_pipeline_notified(pipeline, :source, {:handle_demand, _size, produced})
    await_settled_production(pipeline, produced)
  end

  defp await_settled_production(pipeline, produced) do
    receive do
      {Pipeline, ^pipeline,
       {:handle_child_notification, {{:handle_demand, _size, produced}, :source}}} ->
        await_settled_production(pipeline, produced)
    after
      300 -> produced
    end
  end

  defp refute_end_of_stream(pipeline, sink, timeout) do
    refute_receive {Pipeline, ^pipeline, {:handle_element_end_of_stream, {^sink, :input}}},
                   timeout
  end
end
