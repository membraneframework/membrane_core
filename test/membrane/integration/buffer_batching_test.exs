defmodule Membrane.Integration.BufferBatchingTest do
  @moduledoc false
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Testing.{Pipeline, Sink}

  require Membrane.Core.Message, as: Message

  defmodule PushSource do
    use Membrane.Source

    def_output_pad :output, flow_control: :push, accepted_format: _any

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %Membrane.RemoteStream{}}], state}
    end

    @impl true
    def handle_parent_notification({:send_buffers, buffers}, _ctx, state) do
      {[buffer: {:output, buffers}], state}
    end
  end

  defmodule FilterBehaviour do
    @moduledoc false
    defmacro __using__(input_flow_control: input_flow_control) do
      quote do
        use Membrane.Filter, flow_control_hints?: false

        def_input_pad :input, flow_control: unquote(input_flow_control), accepted_format: _any
        def_output_pad :output, flow_control: :push, accepted_format: _any

        def_options actions_for_buffer: [spec: (Buffer.t() -> [Membrane.Element.Action.t()])]

        @impl true
        def handle_init(_ctx, opts), do: {[], Map.from_struct(opts)}

        @impl true
        def handle_buffer(:input, buffer, _ctx, state) do
          {state.actions_for_buffer.(buffer), state}
        end
      end
    end
  end

  defmodule PushFilter do
    use FilterBehaviour, input_flow_control: :push
  end

  defmodule AutoFilter do
    use FilterBehaviour, input_flow_control: :auto
  end

  defmodule ManualFilter do
    use Membrane.Filter

    def_input_pad :input, flow_control: :manual, accepted_format: _any, demand_unit: :buffers
    def_output_pad :output, flow_control: :push, accepted_format: _any

    def_options actions_for_buffer: [spec: (Buffer.t() -> [Membrane.Element.Action.t()])]

    @impl true
    def handle_init(_ctx, opts), do: {[], Map.from_struct(opts)}

    @impl true
    def handle_playing(_ctx, state), do: {[demand: {:input, 1000}], state}

    @impl true
    def handle_buffer(:input, buffer, _ctx, state) do
      {state.actions_for_buffer.(buffer), state}
    end
  end

  @buffers_count 100
  @buffers Enum.map(1..@buffers_count, &%Buffer{payload: <<&1>>})

  defp forward_buffer(buffer), do: [buffer: {:output, buffer}]

  defp start_pipeline(filter_module, actions_for_buffer) do
    spec =
      child(:source, PushSource)
      |> child(:filter, struct!(filter_module, actions_for_buffer: actions_for_buffer))
      |> child(:sink, Sink)

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_sink_stream_format(pipeline, :sink, %Membrane.RemoteStream{})

    filter_pid = Pipeline.get_child_pid!(pipeline, :filter)
    1 = :erlang.trace(filter_pid, true, [:send])

    {pipeline, filter_pid}
  end

  defp assert_all_buffers_received(pipeline) do
    for buffer <- @buffers do
      assert_sink_buffer(pipeline, :sink, ^buffer)
    end
  end

  defp traced_output_messages(filter_pid) do
    receive do
      {:trace, ^filter_pid, :send, Message.message(type: type, args: args, opts: opts), _to}
      when type in [:buffer, :event] ->
        if opts[:for_pad] == :input,
          do: [{type, args} | traced_output_messages(filter_pid)],
          else: traced_output_messages(filter_pid)

      {:trace, ^filter_pid, :send, _message, _to} ->
        traced_output_messages(filter_pid)
    after
      0 -> []
    end
  end

  for {name, filter_module} <- [push: PushFilter, auto: AutoFilter, manual: ManualFilter] do
    describe "with #{name} input pad" do
      @filter_module filter_module

      test "buffers returned from subsequent handle_buffer calls are sent in a single message" do
        {pipeline, filter_pid} = start_pipeline(@filter_module, &forward_buffer/1)

        Pipeline.notify_child(pipeline, :source, {:send_buffers, @buffers})
        assert_all_buffers_received(pipeline)

        assert [{:buffer, @buffers}] = traced_output_messages(filter_pid)

        Pipeline.terminate(pipeline)
      end

      test "buffers are not merged over other actions" do
        actions_for_buffer = fn %Buffer{payload: <<i>>} = buffer ->
          if rem(i, 10) == 0,
            do: [buffer: {:output, buffer}, event: {:output, %Membrane.Testing.Event{}}],
            else: [buffer: {:output, buffer}]
        end

        {pipeline, filter_pid} = start_pipeline(@filter_module, actions_for_buffer)

        Pipeline.notify_child(pipeline, :source, {:send_buffers, @buffers})
        assert_all_buffers_received(pipeline)

        expected_messages =
          @buffers
          |> Enum.chunk_every(10)
          |> Enum.flat_map(&[{:buffer, &1}, {:event, %Membrane.Testing.Event{}}])

        assert traced_output_messages(filter_pid) == expected_messages

        Pipeline.terminate(pipeline)
      end
    end
  end

  test "buffers are sent before the element starts waiting for the next message" do
    {pipeline, filter_pid} = start_pipeline(PushFilter, &forward_buffer/1)

    [first_half, second_half] = Enum.chunk_every(@buffers, div(@buffers_count, 2))

    Pipeline.notify_child(pipeline, :source, {:send_buffers, first_half})
    for buffer <- first_half, do: assert_sink_buffer(pipeline, :sink, ^buffer)
    assert [{:buffer, ^first_half}] = traced_output_messages(filter_pid)

    Pipeline.notify_child(pipeline, :source, {:send_buffers, second_half})
    for buffer <- second_half, do: assert_sink_buffer(pipeline, :sink, ^buffer)
    assert [{:buffer, ^second_half}] = traced_output_messages(filter_pid)

    Pipeline.terminate(pipeline)
  end

  test "buffers sent through different pads are not reordered" do
    defmodule TwoOutputsFilter do
      use Membrane.Filter

      def_input_pad :input, flow_control: :push, accepted_format: _any
      def_output_pad :output_a, flow_control: :push, accepted_format: _any
      def_output_pad :output_b, flow_control: :push, accepted_format: _any

      @impl true
      def handle_buffer(:input, %Buffer{payload: <<i>>} = buffer, _ctx, state) do
        pad = if rem(i, 10) == 0, do: :output_b, else: :output_a
        {[buffer: {pad, buffer}], state}
      end
    end

    spec = [
      child(:source, PushSource)
      |> child(:filter, TwoOutputsFilter)
      |> via_out(:output_a)
      |> child(:sink_a, Sink),
      get_child(:filter)
      |> via_out(:output_b)
      |> child(:sink_b, Sink)
    ]

    pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_sink_stream_format(pipeline, :sink_a, %Membrane.RemoteStream{})
    assert_sink_stream_format(pipeline, :sink_b, %Membrane.RemoteStream{})

    filter_pid = Pipeline.get_child_pid!(pipeline, :filter)
    1 = :erlang.trace(filter_pid, true, [:send])

    Pipeline.notify_child(pipeline, :source, {:send_buffers, @buffers})

    for %Buffer{payload: <<i>>} = buffer <- @buffers do
      sink = if rem(i, 10) == 0, do: :sink_b, else: :sink_a
      assert_sink_buffer(pipeline, sink, ^buffer)
    end

    expected_messages =
      @buffers
      |> Enum.chunk_every(10)
      |> Enum.flat_map(fn chunk ->
        {to_b, to_a} = Enum.split_with(chunk, fn %Buffer{payload: <<i>>} -> rem(i, 10) == 0 end)
        [{:buffer, to_a}, {:buffer, to_b}]
      end)

    assert traced_output_messages(filter_pid) == expected_messages

    Pipeline.terminate(pipeline)
  end
end
