defmodule Membrane.Integration.AutoDemandsTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions

  alias Membrane.Testing.{Pipeline, Sink, Source}

  defmodule AutoDemandFilter do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any, flow_control: :auto
    def_output_pad :output, accepted_format: _any, flow_control: :auto

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

  defmodule AutoDemandTee do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any, flow_control: :auto
    def_output_pad :output, accepted_format: _any, availability: :on_request, flow_control: :auto

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
      import Membrane.ChildrenSpec

      %{payloads: payloads, factor: factor, direction: direction, filters: filters} =
        unquote(Macro.escape(opts))

      mult_payloads =
        Enum.flat_map(payloads, &Enum.map(1..Integer.pow(factor, filters), fn _i -> &1 end))

      {in_payloads, out_payloads} =
        case direction do
          :up -> {payloads, mult_payloads}
          :down -> {mult_payloads, payloads}
        end

      filter = %AutoDemandFilter{factor: factor, direction: direction}

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

    Pipeline.message_child(pipeline, :right_sink, {:make_demand, 1000})

    Enum.each(1..1000, fn payload ->
      assert_sink_buffer(pipeline, :right_sink, buffer)
      assert buffer.payload == payload
      assert_sink_buffer(pipeline, :left_sink, buffer)
      assert buffer.payload == payload
    end)

    refute_sink_buffer(pipeline, :left_sink, %{payload: 25_000})
  end

  test "handle removed branch" do
    import Membrane.ChildrenSpec

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

    Enum.each(1..100_000, fn payload ->
      assert_sink_buffer(pipeline, :left_sink, buffer)
      assert buffer.payload == payload
    end)
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
      import Membrane.ChildrenSpec

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
      {[stream_format: {:output, %StreamFormat{}}], state}
    end
  end

  test "toilet" do
    import Membrane.ChildrenSpec

    pipeline =
      Pipeline.start_link_supervised!(
        spec:
          child(:source, PushSource)
          |> child(:filter, AutoDemandFilter)
          |> child(:sink, Sink)
      )

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
    import Membrane.ChildrenSpec

    pipeline =
      Pipeline.start_supervised!(
        spec:
          child(:source, PushSource)
          |> child(:filter, AutoDemandFilter)
          |> child(:sink, %Sink{autodemand: false})
      )

    Process.monitor(pipeline)

    buffers = Enum.map(1..100_000, &%Membrane.Buffer{payload: &1})
    Pipeline.message_child(pipeline, :source, buffer: {:output, buffers})
    assert_receive({:DOWN, _ref, :process, ^pipeline, {:shutdown, :child_crash}})
  end

  defp reduce_link(link, enum, fun) do
    Enum.reduce(enum, link, &fun.(&2, &1))
  end
end
