defmodule Membrane.Integration.ElementsCompatibilityTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions
  alias Membrane.Testing.Pipeline

  defmodule StreamFormat do
    defstruct []
  end

  defmodule Utilities do
    @spec buffer() :: list(String.t())
    def buffer, do: ["SOME", "EXEMPLARY", "MESSAGES", "BEING", "SENT", "TO", "OUTPUT"]
  end

  # ========================== SOURCES ===================================

  defmodule PullBuffersSource do
    use Membrane.Source

    def_output_pad :output,
      accepted_format: _any,
      mode: :pull,
      demand_mode: :manual,
      demand_unit: :buffers

    @impl true
    def handle_init(_ctx, _opts) do
      {[], Utilities.buffer()}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %StreamFormat{}}], state}
    end

    @impl true
    def handle_demand(pad, _size, :buffers, _ctx, state) do
      case state do
        [first | rest] ->
          {[buffer: {:output, %Membrane.Buffer{payload: first}}, redemand: pad], rest}

        [] ->
          {[end_of_stream: :output], []}
      end
    end
  end

  defmodule PullBytesSource do
    use Membrane.Source

    def_output_pad :output,
      accepted_format: _any,
      mode: :pull,
      demand_mode: :manual,
      demand_unit: :bytes

    @impl true
    def handle_init(_ctx, _opts) do
      {[], Utilities.buffer()}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %StreamFormat{}}], state}
    end

    @impl true
    def handle_demand(pad, _size, :bytes, _ctx, state) do
      case state do
        [first | rest] ->
          {[buffer: {:output, %Membrane.Buffer{payload: first}}, redemand: pad], rest}

        [] ->
          {[end_of_stream: :output], []}
      end
    end
  end

  defmodule PushSource do
    use Membrane.Source

    def_output_pad :output, accepted_format: _any, mode: :push

    @impl true
    def handle_init(_ctx, _opts) do
      {[], Utilities.buffer()}
    end

    @impl true
    def handle_playing(_ctx, state) do
      buffers_actions = Enum.map(state, &{:buffer, {:output, %Membrane.Buffer{payload: &1}}})

      {[stream_format: {:output, %StreamFormat{}}] ++ buffers_actions ++ [end_of_stream: :output],
       []}
    end
  end

  # ======================================= FILTERS =============================================
  defmodule AutodemandFilter do
    use Membrane.Filter

    def_input_pad :input,
      accepted_format: _any,
      mode: :pull,
      demand_mode: :auto

    def_output_pad :output,
      accepted_format: _any,
      mode: :pull,
      demand_mode: :auto

    @impl true
    def handle_init(_ctx, _opts) do
      {[], nil}
    end

    @impl true
    def handle_playing(ctx, state) do
      if ctx.pads.output.demand_unit != ctx.pads.output.other_demand_unit do
        raise "Autodemand demand unit resolved improperly"
      end

      if ctx.pads.input[:other_demand_unit] != nil and
           ctx.pads.input.demand_unit != ctx.pads.input.other_demand_unit do
        raise "Autodemand demand unit resolved improperly"
      end

      {[], state}
    end

    @impl true
    def handle_process(:input, buf, _ctx, state) do
      {[buffer: {:output, buf}], state}
    end
  end

  # ======================================== SINKS ==============================================

  defmodule PullBuffersSink do
    use Membrane.Sink

    def_input_pad :input,
      accepted_format: _any,
      mode: :pull,
      demand_mode: :manual,
      demand_unit: :buffers

    def_options test_pid: [spec: pid()]

    @impl true
    def handle_init(_ctx, opts) do
      {[], %{test_pid: opts.test_pid, buffers: [], demanded: 0, received: 0}}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[demand: {:input, 2}], %{state | demanded: 2}}
    end

    @impl true
    def handle_write(_pad, buffer, _ctx, state) do
      state = %{state | buffers: [buffer.payload | state.buffers], received: state.received + 1}

      cond do
        state.received < state.demanded ->
          {[], state}

        state.received == state.demanded ->
          Process.send_after(self(), :demand, 10)
          {[], state}

        state.received > state.demanded ->
          raise "Received more then demanded"
      end
    end

    @impl true
    def handle_info(:demand, _ctx, state) do
      {[demand: {:input, 2}], %{state | demanded: state.demanded + 2}}
    end

    @impl true
    def handle_end_of_stream(_pad, _ctx, state) do
      send(state.test_pid, {:state_dump, state.buffers})
      {[], state}
    end
  end

  defmodule PullBytesSink do
    use Membrane.Sink

    def_input_pad :input,
      accepted_format: _any,
      mode: :pull,
      demand_mode: :manual,
      demand_unit: :bytes

    def_options test_pid: [spec: pid()]

    @impl true
    def handle_init(_ctx, opts) do
      {[], %{test_pid: opts.test_pid, buffers: [], demanded: 0, received: 0}}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[demand: {:input, 2}], %{state | demanded: 2}}
    end

    @impl true
    def handle_write(_pad, buffer, _ctx, state) do
      state = %{
        state
        | buffers: [buffer.payload | state.buffers],
          received: state.received + byte_size(buffer.payload)
      }

      cond do
        state.received < state.demanded ->
          {[], state}

        state.received == state.demanded ->
          Process.send_after(self(), :demand, 10)
          {[], state}

        state.received > state.demanded ->
          raise "Received more then demanded"
      end
    end

    @impl true
    def handle_info(:demand, _ctx, state) do
      {[demand: {:input, 2}], %{state | demanded: state.demanded + 2}}
    end

    @impl true
    def handle_end_of_stream(_pad, _ctx, state) do
      send(state.test_pid, {:state_dump, state.buffers})
      {[], state}
    end
  end

  defp test_sink(source_module, sink_module, should_add_filter?) do
    {:ok, _supervisor_pid, pid} =
      Pipeline.start_link(
        spec:
          child(source_module)
          |> Bunch.then_if(should_add_filter?, &child(&1, AutodemandFilter))
          |> child(sink_module.__struct__(test_pid: self()))
      )

    assert_pipeline_play(pid)

    state_dump =
      receive do
        {:state_dump, state_dump} -> state_dump
      end

    assert Enum.join(Utilities.buffer()) == state_dump |> Enum.reverse() |> Enum.join()
    Pipeline.terminate(pid, blocking?: true)
  end

  test "if sink demanding in bytes receives all the data and no more then demanded number of bytes at once" do
    Enum.each(
      [PushSource, PullBytesSource, PullBuffersSource],
      &test_sink(&1, PullBytesSink, false)
    )
  end

  test "if sink demanding in buffers receives all the data" do
    Enum.each(
      [PushSource, PullBytesSource, PullBuffersSource],
      &test_sink(&1, PullBuffersSink, false)
    )
  end

  test "if sink demanding in bytes receives all the data and no more then demanded number of bytes at once when is preceed by  autodemand filter" do
    Enum.each(
      [PushSource, PullBytesSource, PullBuffersSource],
      &test_sink(&1, PullBytesSink, true)
    )
  end

  test "if sink demanding in buffers receives all the data when is preceed by  autodemand filter" do
    Enum.each(
      [PushSource, PullBytesSource, PullBuffersSource],
      &test_sink(&1, PullBuffersSink, true)
    )
  end
end
