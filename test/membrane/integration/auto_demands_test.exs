defmodule Membrane.Integration.AutoDemandsTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
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

    @impl true
    def handle_playing(_ctx, state), do: {[notify_parent: :playing], state}

    @impl true
    def handle_parent_notification(actions, _ctx, state), do: {actions, state}

    @impl true
    def handle_buffer(pad, buffer, _ctx, state) do
      actions = [
        notify_parent: {:handling_buffer, pad, buffer},
        buffer: {:output, buffer}
      ]

      {actions, state}
    end

    @impl true
    def handle_end_of_stream(_pad, _ctx, state), do: {[], state}
  end

  defmodule AutoDemandTee do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any, availability: :on_request

    @impl true
    def handle_buffer(:input, buffer, _ctx, state), do: {[forward: buffer], state}
  end

  [
    %{payloads: 1..100_000, factor: 1, direction: :up, filters: 10},
    %{payloads: 1..4, factor: 10, direction: :up, filters: 5},
    %{payloads: 1..4, factor: 10, direction: :down, filters: 5}
  ]
  |> Enum.map(fn opts ->
    test "buffers pass through auto-demand filters; setup: #{inspect(opts)}" do
      %{payloads: payloads, factor: factor, direction: direction, filters: filters} =
        unquote(Macro.escape(opts))

      mult_payloads =
        Enum.flat_map(payloads, &Enum.map(1..Integer.pow(factor, filters), fn _i -> &1 end))

      {in_payloads, out_payloads} =
        case direction do
          :up -> {payloads, mult_payloads}
          :down -> {mult_payloads, payloads}
        end

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
  end)

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

    Pipeline.message_child(pipeline, :right_sink, {:make_demand, 1000})

    Enum.each(1..1000, fn payload ->
      assert_sink_buffer(pipeline, :right_sink, buffer)
      assert buffer.payload == payload
      assert_sink_buffer(pipeline, :left_sink, buffer)
      assert buffer.payload == payload
    end)

    refute_sink_buffer(pipeline, :left_sink, %{payload: 25_000})

    Pipeline.terminate(pipeline)
  end

  test "handle removed branch" do
    pipeline =
      Pipeline.start_link_supervised!(
        spec: [
          child(:source, %Source{output: 1..100_000}) |> child(:tee, AutoDemandTee),
          get_child(:tee) |> child(:left_sink, Sink),
          get_child(:tee) |> child(:right_sink, %Sink{autodemand: false})
        ]
      )

    Process.sleep(500)
    Pipeline.execute_actions(pipeline, remove_children: :right_sink)

    IO.puts("START OF THE ASSERTIONS")

    Enum.each(1..100_000, fn payload ->
      # IO.puts("ASSERTION NO. #{inspect(payload)}")

      # if payload == 801 do
      #   Process.sleep(500)

      #   for name <- [
      #     # :source,
      #     :tee
      #     # , :left_sink
      #     ] do
      #     Pipeline.get_child_pid!(pipeline, name)
      #     |> :sys.get_state()
      #     |> IO.inspect(label: "NAME OF #{inspect(name)}", limit: :infinity)
      #   end

      #   Pipeline.get_child_pid!(pipeline, :left_sink)
      #   |> :sys.get_state()
      #   |> get_in([:pads_data, :input, :input_queue])
      #   |> Map.get(:atomic_demand)
      #   |> Membrane.Core.Element.AtomicDemand.get()
      #   |> IO.inspect(label: "ATOMIC DEMAND VALUE")
      # end

      assert_sink_buffer(pipeline, :left_sink, buffer)
      assert buffer.payload == payload
    end)

    Pipeline.terminate(pipeline)
  end

  defmodule NotifyingSink do
    use Membrane.Sink

    def_input_pad :input, accepted_format: _any, flow_control: :auto

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
    Pipeline.message_child(pipeline, :source, buffer: {:output, buffers})

    Enum.each(1..100_010, fn i ->
      assert_sink_buffer(pipeline, :sink, buffer)
      assert buffer.payload == i

      if i <= 100_000 do
        buffer = %Membrane.Buffer{payload: i + 10}
        Pipeline.message_child(pipeline, :source, buffer: {:output, buffer})
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
    Pipeline.message_child(pipeline, :source, buffer: {:output, buffers})

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
        500 -> Enum.reverse(acc)
      end
    end

    test "when there is no demand on the output pad", %{pipeline: pipeline} do
      manual_flow_queue_size = 40

      assert_pipeline_notified(pipeline, :filter, :playing)

      buffers = receive_processed_buffers(pipeline, 100)
      assert length(buffers) == manual_flow_queue_size

      demand = 10_000
      Pipeline.message_child(pipeline, :sink, {:make_demand, demand})

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
      manual_flow_queue_size = 40
      auto_flow_demand_size = 400

      assert_pipeline_notified(pipeline, :filter, :playing)

      Pipeline.message_child(pipeline, :filter, pause_auto_demand: Pad.ref(:input, 0))

      # time for :filter to pause demand on Pad.ref(:input, 0)
      Process.sleep(500)

      buffers = receive_processed_buffers(pipeline, 100)
      assert length(buffers) == manual_flow_queue_size

      demand = 10_000
      Pipeline.message_child(pipeline, :sink, {:make_demand, demand})

      # fliter paused auto demand on Pad.ref(:input, 0), so it should receive
      # at most auto_flow_demand_size buffers from there and rest of the buffers
      # from Pad.ref(:input, 1)
      buffers = receive_processed_buffers(pipeline, 2 * demand)
      buffers_number = length(buffers)

      assert demand <= buffers_number
      assert buffers_number <= demand + manual_flow_queue_size

      counter_0 = Map.fetch!(buffers_by_creator, {:source, 0}, []) |> length()
      counter_1 = Map.fetch!(buffers_by_creator, {:source, 1}) |> length()

      # at most auto_flow_demand_size buffers came from {:source, 0}
      assert auto_flow_demand_size - manual_flow_queue_size <= counter_0
      assert counter_0 <= auto_flow_demand_size

      # rest of them came from {:source, 1}
      assert demand - auto_flow_demand_size <= counter_1

      Pipeline.message_child(pipeline, :filter, resume_auto_demand: Pad.ref(:input, 0))

      # time for :filter to resume demand on Pad.ref(:input, 0)
      Process.sleep(500)

      Pipeline.message_child(pipeline, :sink, {:make_demand, demand})

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

  defp reduce_link(link, enum, fun) do
    Enum.reduce(enum, link, &fun.(&2, &1))
  end
end
