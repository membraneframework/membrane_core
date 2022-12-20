defmodule Membrane.Integration.ElementsCompatibilityTest do
  use ExUnit.Case, async: true

  defmodule StreamFormat do
    defstruct []
  end

  defmodule Utilities do
    def buffer, do: ["SOME", "EXEMPLARY", "MESSAGES", "BEING", "SENT", "TO", "OUTPUT"]
  end

  # ======================= SOURCES ====================================================

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

  # ======================================== SINKS ========================================================

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
      {[], %{test_pid: opts.test_pid, buffers: []}}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[demand: {:input, 2}], state}
    end

    @impl true
    def handle_write(_pad, buffer, _ctx, state) do
      state = %{state | buffers: [buffer.payload | state.buffers]}
      {[demand: {:input, 2}], state}
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
      {[], %{test_pid: opts.test_pid, buffers: []}}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[demand: {:input, 2}], state}
    end

    @impl true
    def handle_write(_pad, buffer, _ctx, state) do
      if byte_size(buffer.payload) > 2 do
        raise "Too large buffer!"
      end

      state = %{state | buffers: [buffer.payload | state.buffers]}
      {[demand: {:input, 2}], state}
    end

    @impl true
    def handle_end_of_stream(_pad, _ctx, state) do
      send(state.test_pid, {:state_dump, state.buffers})
      {[], state}
    end
  end

  import Membrane.ChildrenSpec
  alias Membrane.Testing.Pipeline
  import Membrane.Testing.Assertions

  defp test_sink(source_module) do
    {:ok, _supervisor_pid, pid} =
      Pipeline.start(spec: child(source_module) |> child(%PullBytesSink{test_pid: self()}))

    assert_pipeline_play(pid)

    state_dump =
      receive do
        {:state_dump, state_dump} -> state_dump
      end

    assert Enum.join(Utilities.buffer()) == state_dump |> Enum.reverse() |> Enum.join()
    Pipeline.terminate(pid, blocking?: true)
  end

  test "if sink demanding in bytes receives all the data and no more then demanded number of bytes at once" do
    Enum.each([PushSource, PullBytesSource, PullBuffersSource], &test_sink(&1))
  end

  test "if sink demanding in buffers receives all the data" do
    Enum.each([PushSource, PullBytesSource, PullBuffersSource], &test_sink(&1))
  end
end
