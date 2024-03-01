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

  defp assert_buffers_received(range, pid) do
    Enum.each(range, fn i ->
      assert_sink_buffer(pid, :sink, buffer)
      assert %Buffer{payload: <<^i::16>> <> <<255>>} = buffer
    end)
  end

  defp test_pipeline(pid) do
    assert_sink_playing(pid, :sink)

    demand = 500
    Pipeline.message_child(pid, :sink, {:make_demand, demand})

    0..(demand - 1)
    |> assert_buffers_received(pid)

    pattern = %Buffer{payload: <<demand::16>> <> <<255>>}
    refute_sink_buffer(pid, :sink, ^pattern, 0)
    Pipeline.message_child(pid, :sink, {:make_demand, demand})

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
  end

  test "Pipeline with filter underestimating demand" do
    filter_demand_gen = fn _incoming_demand -> 2 end

    links =
      child(:source, Source)
      |> child(:filter, %Filter{demand_generator: filter_demand_gen})
      |> child(:sink, %Sink{autodemand: false})

    pid = Pipeline.start_link_supervised!(spec: links)
    test_pipeline(pid)
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
      buffer = %Membrane.Buffer{buffer | metadata: pad}

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
end
