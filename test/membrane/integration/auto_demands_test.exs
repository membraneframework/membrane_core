defmodule Membrane.Integration.AutoDemandsTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Support.DemandsTest.{ControlledSource, ReportingSource}
  alias Membrane.Testing.{Pipeline, Sink, Source}

  require Membrane.Pad, as: Pad

  defmodule ExponentialAutoFilter do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any

    def_options factor: [default: 1], direction: [default: :up]

    @impl true
    def handle_init(_ctx, opts) do
      {[], opts |> Map.from_struct() |> Map.merge(%{counter: 1})}
    end

    @impl true
    def handle_buffer(:input, buffer, _ctx, %{direction: :up} = state) do
      buffers = Enum.map(1..state.factor, fn _i -> buffer end)
      {[buffer: {:output, buffers}], state}
    end

    @impl true
    def handle_buffer(:input, buffer, _ctx, %{direction: :down} = state) do
      if state.counter < state.factor do
        {[], %{state | counter: state.counter + 1}}
      else
        {[buffer: {:output, buffer}], %{state | counter: 1}}
      end
    end
  end

  defmodule NotifyingAutoFilter do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any, availability: :on_request
    def_output_pad :output, accepted_format: _any

    def_options initially_paused_pads: [spec: [Pad.ref()], default: []]

    @impl true
    def handle_init(_ctx, opts), do: {[], Map.from_struct(opts)}

    @impl true
    def handle_playing(_ctx, state) do
      pause_actions = Enum.map(state.initially_paused_pads, &{:pause_auto_demand, &1})
      {pause_actions ++ [notify_parent: :playing], state}
    end

    @impl true
    def handle_parent_notification(actions, _ctx, state), do: {actions, state}

    @impl true
    def handle_stream_format(pad, stream_format, _ctx, state) do
      actions = [
        notify_parent: {:handling_stream_format, pad, stream_format},
        stream_format: {:output, stream_format}
      ]

      {actions, state}
    end

    @impl true
    def handle_buffer(pad, buffer, _ctx, state) do
      actions = [
        notify_parent: {:handling_buffer, pad, buffer},
        buffer: {:output, buffer}
      ]

      {actions, state}
    end

    @impl true
    def handle_event(pad, event, _ctx, state) do
      actions = [
        notify_parent: {:handling_event, pad, event},
        event: {:output, event}
      ]

      {actions, state}
    end

    @impl true
    def handle_end_of_stream(pad, ctx, state) do
      all_inputs_ended? =
        ctx.pads
        |> Map.values()
        |> Enum.all?(&(&1.direction == :output or &1.end_of_stream?))

      eos_actions = if all_inputs_ended?, do: [end_of_stream: :output], else: []
      {[notify_parent: {:end_of_stream, pad}] ++ eos_actions, state}
    end
  end

  defmodule AutoDemandTee do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any, availability: :on_request

    @impl true
    def handle_pad_added(pad, %{playback: :playing} = ctx, state) do
      case ctx.pads.input.stream_format do
        nil -> {[], state}
        stream_format -> {[stream_format: {pad, stream_format}], state}
      end
    end

    @impl true
    def handle_pad_added(_pad, _ctx, state), do: {[], state}

    @impl true
    def handle_parent_notification(actions, _ctx, state), do: {actions, state}

    @impl true
    def handle_buffer(:input, buffer, ctx, state) do
      {Enum.map(open_output_pads(ctx), &{:buffer, {&1, buffer}}), state}
    end

    @impl true
    def handle_end_of_stream(:input, ctx, state) do
      {Enum.map(open_output_pads(ctx), &{:end_of_stream, &1}), state}
    end

    defp open_output_pads(ctx) do
      for {pad, %{direction: :output, end_of_stream?: false}} <- ctx.pads, do: pad
    end
  end

  defmodule BlockingSink do
    use Membrane.Sink

    def_input_pad :input, accepted_format: _any, flow_control: :auto

    @impl true
    def handle_init(_ctx, _opts), do: {[], %{unblocked?: false}}

    @impl true
    def handle_buffer(:input, buffer, ctx, %{unblocked?: false} = state) do
      receive do
        :unblock -> handle_buffer(:input, buffer, ctx, %{state | unblocked?: true})
      end
    end

    @impl true
    def handle_buffer(:input, buffer, _ctx, state) do
      {[notify_parent: {:buffer, buffer.payload}], state}
    end

    @impl true
    def handle_info(:unblock, _ctx, state), do: {[], %{state | unblocked?: true}}
  end

  defmodule NotifyingSink do
    use Membrane.Sink

    def_input_pad :input, accepted_format: _any, flow_control: :auto

    @impl true
    def handle_playing(_ctx, state), do: {[notify_parent: :playing], state}

    @impl true
    def handle_buffer(:input, buffer, _ctx, state) do
      {[notify_parent: {:buffer_arrived, buffer}], state}
    end
  end

  defmodule NotifyingEndpoint do
    use Membrane.Endpoint

    def_input_pad :input, accepted_format: _any, flow_control: :auto

    @impl true
    def handle_buffer(:input, buffer, _ctx, state) do
      {[notify_parent: {:buffer_arrived, buffer}], state}
    end
  end

  [
    %{payloads: 1..100_000, factor: 1, direction: :up, filters: 10},
    %{payloads: 1..4, factor: 10, direction: :up, filters: 5},
    %{payloads: 1..4, factor: 10, direction: :down, filters: 5}
  ]
  |> Enum.map(fn opts ->
    test "buffers pass through auto-demand filters; setup: #{inspect(opts)}" do
      opts = unquote(Macro.escape(opts))
      test_auto_demand_filters(opts)
    end
  end)

  defp test_auto_demand_filters(%{
         payloads: payloads,
         factor: factor,
         direction: direction,
         filters: filters
       }) do
    mult_payloads =
      Enum.flat_map(payloads, &Enum.map(1..Integer.pow(factor, filters), fn _i -> &1 end))

    {in_payloads, out_payloads} =
      if direction == :up,
        do: {payloads, mult_payloads},
        else: {mult_payloads, payloads}

    filter = %ExponentialAutoFilter{factor: factor, direction: direction}

    pipeline =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %Source{output: in_payloads})
          |> reduce_link(1..filters, &child(&1, {:filter, &2}, filter))
          |> child(:sink, Sink)
      )

    Enum.each(out_payloads, fn payload ->
      assert_sink_buffer(pipeline, :sink, buffer)
      assert buffer.payload == payload
    end)

    assert_end_of_stream(pipeline, :sink)
    refute_sink_buffer(pipeline, :sink, _buffer, 0)

    Pipeline.terminate(pipeline)
  end

  test "buffers pass through auto-demand tee" do
    import Membrane.ChildrenSpec

    pipeline =
      Pipeline.start_link_supervised!(
        spec: [
          child(:source, %Source{output: 1..100_000}) |> child(:tee, AutoDemandTee),
          get_child(:tee) |> child(:left_sink, Sink),
          get_child(:tee) |> child(:right_sink, %Sink{autodemand: false})
        ]
      )

    assert_sink_playing(pipeline, :right_sink)

    Pipeline.notify_child(pipeline, :right_sink, {:make_demand, 1000})

    Enum.each(1..1000, fn payload ->
      assert_sink_buffer(pipeline, :right_sink, buffer)
      assert buffer.payload == payload
      assert_sink_buffer(pipeline, :left_sink, buffer)
      assert buffer.payload == payload
    end)

    refute_sink_buffer(pipeline, :left_sink, %{payload: 25_000})

    Pipeline.terminate(pipeline)
  end

  @tee_auto_demand_size 400
  @tee_payloads_count 3000
  @slow_sink_queue_size 10
  @first_slow_sink_demand 500

  [
    {"one output pad without demand corks the tee until its sink demands", :demand},
    {"end of stream on the undemanded output uncorks the other output", :end_of_stream},
    {"handle removed branch", :removal}
  ]
  |> Enum.map(fn {test_name, uncorking_trigger} ->
    @tag :vibe_coded
    test test_name do
      uncorking_trigger = unquote(uncorking_trigger)

      pipeline =
        Pipeline.start_link_supervised!(
          spec: [
            child(:source, %Source{output: 1..@tee_payloads_count}) |> child(:tee, AutoDemandTee),
            get_child(:tee) |> via_out(Pad.ref(:output, :fast)) |> child(:fast_sink, Sink),
            get_child(:tee)
            |> via_out(Pad.ref(:output, :slow))
            |> via_in(:input, target_queue_size: @slow_sink_queue_size)
            |> child(:slow_sink, %Sink{autodemand: false})
          ]
        )

      assert_sink_playing(pipeline, :slow_sink)

      stalled_at = drain_sink_payloads(pipeline, :fast_sink, 1)
      assert stalled_at in @slow_sink_queue_size..@tee_auto_demand_size
      refute_sink_buffer(pipeline, :slow_sink, _buffer, 0)

      fast_sink_received_until = uncork_tee(pipeline, uncorking_trigger, stalled_at)

      assert_sink_payloads(
        pipeline,
        :fast_sink,
        (fast_sink_received_until + 1)..@tee_payloads_count
      )

      assert_end_of_stream(pipeline, :fast_sink)
      assert_slow_sink_completed(pipeline, uncorking_trigger, stalled_at)

      Pipeline.terminate(pipeline)
    end
  end)

  defp uncork_tee(pipeline, :demand, stalled_at) do
    Pipeline.notify_child(pipeline, :slow_sink, {:make_demand, @first_slow_sink_demand})
    assert_sink_payloads(pipeline, :slow_sink, 1..@first_slow_sink_demand)

    resumed_until = drain_sink_payloads(pipeline, :fast_sink, stalled_at + 1)
    assert resumed_until >= @first_slow_sink_demand
    assert resumed_until - stalled_at <= @tee_auto_demand_size
    refute_sink_buffer(pipeline, :slow_sink, _buffer, 0)

    remaining_demand = @tee_payloads_count - @first_slow_sink_demand
    Pipeline.notify_child(pipeline, :slow_sink, {:make_demand, remaining_demand})
    resumed_until
  end

  defp uncork_tee(pipeline, :end_of_stream, stalled_at) do
    Pipeline.notify_child(pipeline, :tee, end_of_stream: Pad.ref(:output, :slow))
    stalled_at
  end

  defp uncork_tee(pipeline, :removal, stalled_at) do
    Pipeline.execute_actions(pipeline, remove_children: :slow_sink)
    stalled_at
  end

  defp assert_slow_sink_completed(pipeline, :demand, _stalled_at) do
    assert_sink_payloads(pipeline, :slow_sink, (@first_slow_sink_demand + 1)..@tee_payloads_count)
    assert_end_of_stream(pipeline, :slow_sink)
  end

  defp assert_slow_sink_completed(pipeline, :end_of_stream, stalled_at) do
    Pipeline.notify_child(pipeline, :slow_sink, {:make_demand, @tee_payloads_count})
    assert_sink_payloads(pipeline, :slow_sink, 1..stalled_at)
    assert_end_of_stream(pipeline, :slow_sink)
    refute_sink_buffer(pipeline, :slow_sink, _buffer, 0)
  end

  defp assert_slow_sink_completed(_pipeline, :removal, _stalled_at), do: :ok

  @tag :vibe_coded
  test "big batches flow through a corked auto filter only as far as the sink demands" do
    filter_auto_demand_size = 400
    batch_size = 500
    payloads_count = 5 * batch_size
    demands = [1, 1, 100]
    final_demand = payloads_count - Enum.sum(demands)

    pipeline =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %ReportingSource{payloads_count: payloads_count, batch_size: batch_size})
          |> child(:filter, ExponentialAutoFilter)
          |> via_in(:input, target_queue_size: 1)
          |> child(:sink, %Sink{autodemand: false})
      )

    assert_sink_playing(pipeline, :sink)

    assert_pipeline_notified(
      pipeline,
      :source,
      {:handle_demand, ^filter_auto_demand_size, ^batch_size}
    )

    refute_sink_buffer(pipeline, :sink, _buffer, 300)

    next_payload =
      Enum.reduce(demands, 1, fn demand, next_payload ->
        Pipeline.notify_child(pipeline, :sink, {:make_demand, demand})
        assert_sink_payloads(pipeline, :sink, next_payload..(next_payload + demand - 1))
        refute_sink_buffer(pipeline, :sink, _buffer, 0)
        refute_pipeline_notified(pipeline, :source, {:handle_demand, _size, _produced}, 300)
        next_payload + demand
      end)

    Pipeline.notify_child(pipeline, :sink, {:make_demand, final_demand})
    assert_sink_payloads(pipeline, :sink, next_payload..payloads_count)
    assert_pipeline_notified(pipeline, :source, {:handle_demand, _size, ^payloads_count})
    assert_end_of_stream(pipeline, :sink)

    Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "items queued on a corked auto input keep their order" do
    sink_queue_size = 5
    first_stream_format = %Membrane.RemoteStream{}
    second_stream_format = %Membrane.RemoteStream{type: :packetized}
    first_event = %Membrane.Event.Discontinuity{duration: 1}
    second_event = %Membrane.Event.Discontinuity{duration: 2}

    pipeline =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, ControlledSource)
          |> child(:filter, NotifyingAutoFilter)
          |> via_in(:input, target_queue_size: sink_queue_size)
          |> child(:sink, %Sink{autodemand: false})
      )

    assert_pipeline_notified(pipeline, :filter, :playing)
    assert_pipeline_notified(pipeline, :source, :playing)
    assert_sink_playing(pipeline, :sink)

    source_actions =
      Enum.map(1..10, &{:buffer, {:output, %Buffer{payload: &1}}}) ++
        [
          event: {:output, first_event},
          stream_format: {:output, second_stream_format}
        ] ++
        Enum.map(11..20, &{:buffer, {:output, %Buffer{payload: &1}}}) ++
        [event: {:output, second_event}, end_of_stream: :output]

    Enum.each(source_actions, &Pipeline.notify_child(pipeline, :source, [&1]))

    handled_before_demand =
      [{:stream_format, first_stream_format}] ++ Enum.map(1..sink_queue_size, &{:buffer, &1})

    handled_after_demand =
      Enum.map((sink_queue_size + 1)..10, &{:buffer, &1}) ++
        [{:event, first_event}, {:stream_format, second_stream_format}] ++
        Enum.map(11..20, &{:buffer, &1}) ++ [{:event, second_event}, :end_of_stream]

    assert_notified_in_order(pipeline, :filter, handled_before_demand)
    refute_pipeline_notified(pipeline, :filter, _notification, 300)
    assert_notified_in_order(pipeline, :sink, [{:stream_format, first_stream_format}])
    refute_sink_buffer(pipeline, :sink, _buffer, 0)

    Pipeline.notify_child(pipeline, :sink, {:make_demand, 100})

    assert_notified_in_order(pipeline, :filter, handled_after_demand)

    assert_notified_in_order(
      pipeline,
      :sink,
      [:start_of_stream] ++ Enum.map(1..sink_queue_size, &{:buffer, &1}) ++ handled_after_demand
    )

    assert_end_of_stream(pipeline, :sink)

    Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "auto output pad linked while playing corks the tee until the new sink demands" do
    tee_auto_demand_size = 400
    sink_a_queue_size = 100
    payloads_count = 5000
    first_demand = 100

    pipeline =
      start_tee_with_demanding_sink_a(payloads_count, sink_a_queue_size, first_demand)

    Pipeline.execute_actions(pipeline,
      spec: get_child(:tee) |> child(:sink_b, %Sink{autodemand: false})
    )

    assert_sink_playing(pipeline, :sink_b)
    refute_sink_buffer(pipeline, :sink_b, _buffer, 0)

    Pipeline.notify_child(pipeline, :sink_a, {:make_demand, payloads_count})
    stalled_at = drain_sink_payloads(pipeline, :sink_a, first_demand + 1)
    assert stalled_at in tee_auto_demand_size..(2 * tee_auto_demand_size)
    refute_sink_buffer(pipeline, :sink_b, _buffer, 0)

    Pipeline.notify_child(pipeline, :sink_b, {:make_demand, payloads_count})

    assert_sink_stream_format(pipeline, :sink_b, %Membrane.RemoteStream{})
    assert_sink_buffer(pipeline, :sink_b, %Buffer{payload: first_sink_b_payload})
    assert first_sink_b_payload == tee_auto_demand_size + 1
    assert_sink_payloads(pipeline, :sink_b, (first_sink_b_payload + 1)..payloads_count)
    assert_sink_payloads(pipeline, :sink_a, (stalled_at + 1)..payloads_count)
    assert_end_of_stream(pipeline, :sink_a)
    assert_end_of_stream(pipeline, :sink_b)

    Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "auto output pad linked while playing corks the tee while its sink does not demand" do
    tee_auto_demand_size = 400
    sink_a_queue_size = 100
    payloads_count = 5000
    first_demand = 100

    pipeline =
      start_tee_with_demanding_sink_a(payloads_count, sink_a_queue_size, first_demand)

    Pipeline.execute_actions(pipeline,
      spec:
        get_child(:tee) |> via_in(:input, auto_demand_size: 0) |> child(:sink_b, NotifyingSink)
    )

    assert_pipeline_notified(pipeline, :sink_b, :playing)

    Pipeline.notify_child(pipeline, :sink_a, {:make_demand, payloads_count})
    stalled_at = drain_sink_payloads(pipeline, :sink_a, first_demand + 1)
    assert stalled_at in sink_a_queue_size..tee_auto_demand_size
    refute_pipeline_notified(pipeline, :sink_b, {:buffer_arrived, _buffer}, 0)

    Pipeline.execute_actions(pipeline, remove_children: :sink_b)

    assert_sink_payloads(pipeline, :sink_a, (stalled_at + 1)..payloads_count)
    assert_end_of_stream(pipeline, :sink_a)

    Pipeline.terminate(pipeline)
  end

  defp start_tee_with_demanding_sink_a(payloads_count, sink_a_queue_size, first_demand) do
    pipeline =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %Source{output: 1..payloads_count})
          |> child(:tee, AutoDemandTee)
          |> via_in(:input, target_queue_size: sink_a_queue_size)
          |> child(:sink_a, %Sink{autodemand: false})
      )

    assert_sink_playing(pipeline, :sink_a)
    Pipeline.notify_child(pipeline, :sink_a, {:make_demand, first_demand})
    assert_sink_payloads(pipeline, :sink_a, 1..first_demand)
    refute_sink_buffer(pipeline, :sink_a, _buffer, 0)
    pipeline
  end

  @tag :vibe_coded
  test "auto input pad linked to a funnel while playing is demanded" do
    buffers_before_link = 50
    buffers_after_link = 50
    linked_source_payloads_count = 500

    pipeline =
      Pipeline.start_link_supervised!(
        spec:
          child(:source_1, ControlledSource)
          |> via_in(Pad.ref(:input, 1))
          |> child(:funnel, Membrane.Funnel)
          |> child(:sink, Sink)
      )

    assert_pipeline_notified(pipeline, :source_1, :playing)
    send_source_buffers(pipeline, :source_1, tagged_payloads(1, 1..buffers_before_link))
    assert_sink_payloads(pipeline, :sink, tagged_payloads(1, 1..buffers_before_link))

    Pipeline.execute_actions(pipeline,
      spec:
        child(:source_2, %Source{output: tagged_payloads(2, 1..linked_source_payloads_count)})
        |> via_in(Pad.ref(:input, 2))
        |> get_child(:funnel)
    )

    assert_sink_payloads(pipeline, :sink, tagged_payloads(2, 1..linked_source_payloads_count))

    later_payloads =
      tagged_payloads(1, (buffers_before_link + 1)..(buffers_before_link + buffers_after_link))

    send_source_buffers(pipeline, :source_1, later_payloads)
    assert_sink_payloads(pipeline, :sink, later_payloads)

    Pipeline.notify_child(pipeline, :source_1, end_of_stream: :output)
    assert_end_of_stream(pipeline, :sink)

    Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "pausing auto demand on one input stops only that input until it is resumed" do
    paused_pad_auto_demand_size = 20
    payloads_count = 300

    pipeline =
      Pipeline.start_link_supervised!(
        spec: [
          child({:source, 0}, %Source{output: tagged_payloads(0, 1..payloads_count)})
          |> via_in(Pad.ref(:input, 0), auto_demand_size: paused_pad_auto_demand_size)
          |> child(:filter, %NotifyingAutoFilter{initially_paused_pads: [Pad.ref(:input, 0)]})
          |> child(:sink, Sink),
          child({:source, 1}, %Source{output: tagged_payloads(1, 1..payloads_count)})
          |> via_in(Pad.ref(:input, 1))
          |> get_child(:filter)
        ]
      )

    assert_pipeline_notified(pipeline, :filter, {:end_of_stream, Pad.ref(:input, 1)})
    payloads_by_source = pipeline |> drain_sink_buffers(:sink) |> Enum.group_by(&elem(&1, 0))
    assert payloads_by_source[1] == tagged_payloads(1, 1..payloads_count)

    paused_source_payloads = Map.get(payloads_by_source, 0, [])
    paused_source_sent = length(paused_source_payloads)
    assert paused_source_sent <= paused_pad_auto_demand_size
    assert paused_source_payloads == tagged_payloads(0, 1..paused_source_sent//1)
    refute_receive {Pipeline, ^pipeline, {:handle_element_end_of_stream, {:sink, :input}}}, 0

    Pipeline.notify_child(pipeline, :filter, resume_auto_demand: Pad.ref(:input, 0))

    assert_sink_payloads(
      pipeline,
      :sink,
      tagged_payloads(0, (paused_source_sent + 1)..payloads_count)
    )

    assert_end_of_stream(pipeline, :sink)

    Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "pausing auto demand on a corked input still delivers its queued buffers" do
    filter_auto_demand_size = 400
    sink_queue_size = 10
    source_batch_size = sink_queue_size
    payloads_count = 3000

    pipeline =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %ReportingSource{
            payloads_count: payloads_count,
            batch_size: source_batch_size
          })
          |> via_in(Pad.ref(:input, 0))
          |> child(:filter, NotifyingAutoFilter)
          |> via_in(:input, target_queue_size: sink_queue_size)
          |> child(:sink, %Sink{autodemand: false})
      )

    assert_pipeline_notified(pipeline, :filter, :playing)
    assert_sink_playing(pipeline, :sink)

    assert_notified_in_order(
      pipeline,
      :filter,
      [{:stream_format, %Membrane.RemoteStream{}}] ++
        Enum.map(1..sink_queue_size, &{:buffer, &1})
    )

    refute_pipeline_notified(pipeline, :filter, _notification, 300)

    Pipeline.notify_child(pipeline, :filter, pause_auto_demand: Pad.ref(:input, 0))
    Pipeline.notify_child(pipeline, :sink, {:make_demand, payloads_count})
    assert_sink_payloads(pipeline, :sink, 1..filter_auto_demand_size)
    refute_sink_buffer(pipeline, :sink, _buffer, 300)

    Pipeline.notify_child(pipeline, :filter, resume_auto_demand: Pad.ref(:input, 0))
    assert_sink_payloads(pipeline, :sink, (filter_auto_demand_size + 1)..payloads_count)
    assert_end_of_stream(pipeline, :sink)

    Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "auto sink blocked in handle_buffer bounds the production of a manual source" do
    sink_auto_demand_size = 50
    payloads_count = 300

    pipeline =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %ReportingSource{payloads_count: payloads_count})
          |> via_in(:input, auto_demand_size: sink_auto_demand_size)
          |> child(:sink, BlockingSink)
      )

    assert_pipeline_notified(
      pipeline,
      :source,
      {:handle_demand, ^sink_auto_demand_size, ^sink_auto_demand_size}
    )

    refute_pipeline_notified(pipeline, :source, {:handle_demand, _size, _produced}, 300)
    refute_pipeline_notified(pipeline, :sink, {:buffer, _payload}, 0)

    send(Pipeline.get_child_pid!(pipeline, :sink), :unblock)

    Enum.each(1..payloads_count, fn payload ->
      assert_pipeline_notified(pipeline, :sink, {:buffer, ^payload})
    end)

    assert_pipeline_notified(pipeline, :source, {:handle_demand, _size, ^payloads_count})
    assert_end_of_stream(pipeline, :sink)

    Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "unlinking an auto input with queued buffers keeps the other input's stream in order" do
    sink_queue_size = 10
    payloads_count = 300
    queued_payloads_count = 100

    pipeline =
      Pipeline.start_link_supervised!(
        spec: [
          child({:source, 0}, ControlledSource)
          |> via_in(Pad.ref(:input, 0))
          |> child(:filter, NotifyingAutoFilter)
          |> via_in(:input, target_queue_size: sink_queue_size)
          |> child(:sink, %Sink{autodemand: false}),
          child({:source, 1}, %Source{output: tagged_payloads(1, 1..payloads_count)})
          |> via_in(Pad.ref(:input, 1))
          |> get_child(:filter)
        ]
      )

    assert_pipeline_notified(pipeline, {:source, 0}, :playing)
    assert_pipeline_notified(pipeline, :filter, {:end_of_stream, Pad.ref(:input, 1)})
    send_source_buffers(pipeline, {:source, 0}, tagged_payloads(0, 1..queued_payloads_count))

    refute_pipeline_notified(
      pipeline,
      :filter,
      {:handling_buffer, Pad.ref(:input, 0), _buffer},
      300
    )

    Pipeline.execute_actions(pipeline, remove_children: {:source, 0})
    assert_pipeline_notified(pipeline, :filter, {:end_of_stream, Pad.ref(:input, 0)})

    Pipeline.notify_child(pipeline, :sink, {:make_demand, 2 * payloads_count})
    assert_sink_payloads(pipeline, :sink, tagged_payloads(1, 1..payloads_count))
    assert_end_of_stream(pipeline, :sink)
    refute_sink_buffer(pipeline, :sink, _buffer, 0)

    Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "queued buffers wait while another output pad is still undemanded" do
    tee_auto_demand_size = 400
    sink_queue_size = 10
    source_batch_size = sink_queue_size
    payloads_count = 3000
    first_demand = 500

    pipeline =
      Pipeline.start_link_supervised!(
        spec: [
          child(:source, %ReportingSource{
            payloads_count: payloads_count,
            batch_size: source_batch_size
          })
          |> child(:tee, AutoDemandTee),
          get_child(:tee)
          |> via_in(:input, target_queue_size: sink_queue_size)
          |> child(:sink_a, %Sink{autodemand: false}),
          get_child(:tee)
          |> via_in(:input, target_queue_size: sink_queue_size)
          |> child(:sink_b, %Sink{autodemand: false})
        ]
      )

    assert_sink_playing(pipeline, :sink_a)
    assert_sink_playing(pipeline, :sink_b)
    assert_pipeline_notified(pipeline, :source, {:handle_demand, _size, ^tee_auto_demand_size})

    Pipeline.notify_child(pipeline, :sink_a, {:make_demand, first_demand})
    assert_sink_payloads(pipeline, :sink_a, 1..sink_queue_size)
    refute_sink_buffer(pipeline, :sink_a, _buffer, 300)
    refute_sink_buffer(pipeline, :sink_b, _buffer, 0)

    Pipeline.notify_child(pipeline, :sink_b, {:make_demand, first_demand})
    assert_sink_payloads(pipeline, :sink_b, 1..first_demand)
    assert_sink_payloads(pipeline, :sink_a, (sink_queue_size + 1)..first_demand)

    Pipeline.notify_child(pipeline, :sink_a, {:make_demand, payloads_count - first_demand})
    Pipeline.notify_child(pipeline, :sink_b, {:make_demand, payloads_count - first_demand})
    assert_sink_payloads(pipeline, :sink_a, (first_demand + 1)..payloads_count)
    assert_sink_payloads(pipeline, :sink_b, (first_demand + 1)..payloads_count)
    assert_end_of_stream(pipeline, :sink_a)
    assert_end_of_stream(pipeline, :sink_b)

    Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "resuming auto demand on a corked element does not demand on its input" do
    filter_auto_demand_size = 50
    produced_before_corking = 2 * filter_auto_demand_size
    sink_queue_size = 10
    payloads_count = 1000

    pipeline =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %ReportingSource{payloads_count: payloads_count})
          |> via_in(Pad.ref(:input, 0), auto_demand_size: filter_auto_demand_size)
          |> child(:filter, NotifyingAutoFilter)
          |> via_in(:input, target_queue_size: sink_queue_size)
          |> child(:sink, %Sink{autodemand: false})
      )

    assert_pipeline_notified(
      pipeline,
      :source,
      {:handle_demand, ^filter_auto_demand_size, ^filter_auto_demand_size}
    )

    assert_pipeline_notified(
      pipeline,
      :source,
      {:handle_demand, ^filter_auto_demand_size, ^produced_before_corking}
    )

    assert_pipeline_notified(
      pipeline,
      :filter,
      {:handling_buffer, _pad, %Buffer{payload: ^filter_auto_demand_size}}
    )

    refute_pipeline_notified(pipeline, :source, {:handle_demand, _size, _produced}, 300)

    Pipeline.notify_child(pipeline, :filter, resume_auto_demand: Pad.ref(:input, 0))
    refute_pipeline_notified(pipeline, :source, {:handle_demand, _size, _produced}, 300)

    Pipeline.notify_child(pipeline, :sink, {:make_demand, payloads_count})
    assert_sink_payloads(pipeline, :sink, 1..payloads_count)
    assert_end_of_stream(pipeline, :sink)

    Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "auto input pad re-demands exactly its auto_demand_size" do
    sink_auto_demand_size = 50
    payloads_count = 1000

    pipeline =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, %ReportingSource{payloads_count: payloads_count})
          |> via_in(:input, auto_demand_size: sink_auto_demand_size)
          |> child(:sink, NotifyingSink)
      )

    for produced <- sink_auto_demand_size..payloads_count//sink_auto_demand_size do
      assert_pipeline_notified(
        pipeline,
        :source,
        {:handle_demand, ^sink_auto_demand_size, ^produced}
      )
    end

    Enum.each(1..payloads_count, fn payload ->
      assert_pipeline_notified(pipeline, :sink, {:buffer_arrived, %Buffer{payload: ^payload}})
    end)

    assert_end_of_stream(pipeline, :sink)

    Pipeline.terminate(pipeline)
  end

  [
    %{name: :sink, module: NotifyingSink},
    %{name: :endpoint, module: NotifyingEndpoint}
  ]
  |> Enum.map(fn opts ->
    test "buffers pass to auto-demand #{opts.name}" do
      %{name: name, module: module} = unquote(Macro.escape(opts))
      payloads = Enum.map(1..1000, &inspect/1)

      pipeline =
        Pipeline.start_link_supervised!(
          spec:
            child(:source, %Source{output: payloads})
            |> child(name, module)
        )

      for payload <- payloads do
        assert_pipeline_notified(
          pipeline,
          name,
          {:buffer_arrived, %Membrane.Buffer{payload: ^payload}}
        )
      end

      Pipeline.terminate(pipeline)
    end
  end)

  defmodule PushSource do
    use Membrane.Source

    def_output_pad :output, flow_control: :push, accepted_format: _any

    defmodule StreamFormat do
      defstruct []
    end

    @impl true
    def handle_parent_notification(actions, _ctx, state) do
      {actions, state}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %StreamFormat{}}, notify_parent: :playing], state}
    end
  end

  test "toilet" do
    pipeline =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, PushSource)
          |> child(:filter, ExponentialAutoFilter)
          |> child(:sink, Sink)
      )

    assert_pipeline_notified(pipeline, :source, :playing)

    buffers = Enum.map(1..10, &%Membrane.Buffer{payload: &1})
    Pipeline.notify_child(pipeline, :source, buffer: {:output, buffers})

    Enum.each(1..100_010, fn i ->
      assert_sink_buffer(pipeline, :sink, buffer)
      assert buffer.payload == i

      if i <= 100_000 do
        buffer = %Membrane.Buffer{payload: i + 10}
        Pipeline.notify_child(pipeline, :source, buffer: {:output, buffer})
      end
    end)

    Pipeline.terminate(pipeline)
    refute_sink_buffer(pipeline, :sink, _buffer, 0)
  end

  test "toilet overflow" do
    pipeline =
      Pipeline.start_supervised!(
        spec:
          child(:source, PushSource)
          |> child(:filter, ExponentialAutoFilter)
          |> child(:sink, %Sink{autodemand: false})
      )

    Process.monitor(pipeline)

    assert_pipeline_notified(pipeline, :source, :playing)

    buffers = Enum.map(1..100_000, &%Membrane.Buffer{payload: &1})
    Pipeline.notify_child(pipeline, :source, buffer: {:output, buffers})

    assert_receive(
      {:DOWN, _ref, :process, ^pipeline, {:membrane_child_crash, :sink, _sink_reason}}
    )
  end

  defp source_definiton(name) do
    # Testing.Source fed with such actions generator will produce buffers with incremenal
    # sequence of numbers as payloads
    actions_generator =
      fn counter, _size ->
        Process.sleep(1)

        buffer = %Buffer{
          metadata: %{creator: name},
          payload: counter
        }

        actions = [buffer: {:output, buffer}, redemand: :output]
        {actions, counter + 1}
      end

    %Source{output: {1, actions_generator}}
  end

  defp setup_pipeline_with_notifying_auto_filter(_context) do
    pipeline =
      Pipeline.start_link_supervised!(
        spec: [
          child({:source, 0}, source_definiton({:source, 0}))
          |> via_in(Pad.ref(:input, 0))
          |> child(:filter, NotifyingAutoFilter)
          |> child(:sink, %Sink{autodemand: false}),
          child({:source, 1}, source_definiton({:source, 1}))
          |> via_in(Pad.ref(:input, 1))
          |> get_child(:filter)
        ]
      )

    [pipeline: pipeline]
  end

  describe "auto flow queue" do
    setup :setup_pipeline_with_notifying_auto_filter

    test "when there is no demand on the output pad", %{pipeline: pipeline} do
      manual_flow_queue_size = 100

      assert_pipeline_notified(pipeline, :filter, :playing)

      buffers = receive_processed_buffers(pipeline, 100)
      assert length(buffers) == manual_flow_queue_size

      demand = 10_000
      Pipeline.notify_child(pipeline, :sink, {:make_demand, demand})

      buffers = receive_processed_buffers(pipeline, 2 * demand)
      buffers_number = length(buffers)

      # check if filter processed proper number of buffers
      assert demand <= buffers_number
      assert buffers_number <= demand + manual_flow_queue_size

      # check if filter processed buffers from both sources
      buffers_by_creator = Enum.group_by(buffers, & &1.metadata.creator)
      assert Enum.count(buffers_by_creator) == 2

      # check if filter balanced procesesd buffers by their origin - numbers of
      # buffers coming from each source should be similar
      counter_0 = Map.fetch!(buffers_by_creator, {:source, 0}) |> length()
      counter_1 = Map.fetch!(buffers_by_creator, {:source, 1}) |> length()
      sources_ratio = counter_0 / counter_1

      assert 0.8 < sources_ratio and sources_ratio < 1.2

      Pipeline.terminate(pipeline)
    end

    test "when an element returns :pause_auto_demand and :resume_auto_demand action", %{
      pipeline: pipeline
    } do
      manual_flow_queue_size = 100
      auto_flow_demand_size = 400

      assert_pipeline_notified(pipeline, :filter, :playing)

      Pipeline.notify_child(pipeline, :filter, pause_auto_demand: Pad.ref(:input, 0))

      # time for :filter to pause demand on Pad.ref(:input, 0)
      Process.sleep(500)

      buffers = receive_processed_buffers(pipeline, 100)
      assert length(buffers) == manual_flow_queue_size

      demand = 10_000
      Pipeline.notify_child(pipeline, :sink, {:make_demand, demand})

      # fliter paused auto demand on Pad.ref(:input, 0), so it should receive
      # at most auto_flow_demand_size buffers from there and rest of the buffers
      # from Pad.ref(:input, 1)
      buffers = receive_processed_buffers(pipeline, 2 * demand)
      buffers_number = length(buffers)

      assert demand <= buffers_number
      assert buffers_number <= demand + manual_flow_queue_size

      buffers_by_creator = Enum.group_by(buffers, & &1.metadata.creator)
      counter_0 = Map.get(buffers_by_creator, {:source, 0}, []) |> length()
      counter_1 = Map.fetch!(buffers_by_creator, {:source, 1}) |> length()

      # at most auto_flow_demand_size buffers came from {:source, 0}
      assert auto_flow_demand_size - manual_flow_queue_size <= counter_0
      assert counter_0 <= auto_flow_demand_size

      # rest of them came from {:source, 1}
      assert demand - auto_flow_demand_size <= counter_1

      Pipeline.notify_child(pipeline, :filter, resume_auto_demand: Pad.ref(:input, 0))

      # time for :filter to resume demand on Pad.ref(:input, 0)
      Process.sleep(500)

      Pipeline.notify_child(pipeline, :sink, {:make_demand, demand})

      buffers = receive_processed_buffers(pipeline, 2 * demand)
      buffers_number = length(buffers)

      # check if filter processed proper number of buffers
      assert demand <= buffers_number
      assert buffers_number <= demand + manual_flow_queue_size

      # check if filter processed buffers from both sources
      buffers_by_creator = Enum.group_by(buffers, & &1.metadata.creator)
      assert Enum.count(buffers_by_creator) == 2

      # check if filter balanced procesesd buffers by their origin - numbers of
      # buffers coming from each source should be similar
      counter_0 = Map.fetch!(buffers_by_creator, {:source, 0}) |> length()
      counter_1 = Map.fetch!(buffers_by_creator, {:source, 1}) |> length()
      sources_ratio = counter_0 / counter_1

      assert 0.8 < sources_ratio and sources_ratio < 1.2

      Pipeline.terminate(pipeline)
    end
  end

  @stall_timeout 500

  defp receive_processed_buffers(pipeline, limit, acc \\ [])

  defp receive_processed_buffers(_pipeline, limit, acc) when limit <= 0 do
    Enum.reverse(acc)
  end

  defp receive_processed_buffers(pipeline, limit, acc) do
    receive do
      {Pipeline, ^pipeline,
       {:handle_child_notification, {{:handling_buffer, _pad, buffer}, :filter}}} ->
        receive_processed_buffers(pipeline, limit - 1, [buffer | acc])
    after
      @stall_timeout -> Enum.reverse(acc)
    end
  end

  defp drain_sink_buffers(pipeline, sink, acc \\ []) do
    receive do
      {Pipeline, ^pipeline, {:handle_child_notification, {{:buffer, buffer}, ^sink}}} ->
        drain_sink_buffers(pipeline, sink, [buffer.payload | acc])
    after
      @stall_timeout -> Enum.reverse(acc)
    end
  end

  defp drain_sink_payloads(pipeline, sink, next_payload) do
    payloads = drain_sink_buffers(pipeline, sink)
    last_payload = next_payload + length(payloads) - 1
    assert payloads == Enum.to_list(next_payload..last_payload//1)
    last_payload
  end

  defp assert_sink_payloads(pipeline, sink, payloads) do
    Enum.each(payloads, fn payload ->
      assert_sink_buffer(pipeline, sink, buffer)
      assert buffer.payload == payload
    end)
  end

  defp assert_notified_in_order(pipeline, child, expected_items) do
    Enum.each(expected_items, fn expected_item ->
      assert_pipeline_notified(pipeline, child, notification)
      assert received_item(notification) == expected_item
    end)
  end

  defp received_item({:handling_buffer, _pad, buffer}), do: {:buffer, buffer.payload}
  defp received_item({:handling_event, _pad, event}), do: {:event, event}
  defp received_item({:handling_stream_format, _pad, format}), do: {:stream_format, format}
  defp received_item({:buffer, buffer}), do: {:buffer, buffer.payload}
  defp received_item({:event, event}), do: {:event, event}
  defp received_item({:stream_format, _pad, format}), do: {:stream_format, format}
  defp received_item({:start_of_stream, _pad}), do: :start_of_stream
  defp received_item({:end_of_stream, _pad}), do: :end_of_stream
  defp received_item(other), do: other

  defp tagged_payloads(tag, payloads), do: Enum.map(payloads, &{tag, &1})

  defp send_source_buffers(pipeline, source, payloads) do
    buffers = Enum.map(payloads, &%Buffer{payload: &1})
    Pipeline.notify_child(pipeline, source, buffer: {:output, buffers})
  end

  defp reduce_link(link, enum, fun) do
    Enum.reduce(enum, link, &fun.(&2, &1))
  end
end
