defmodule Membrane.FailWhenNoCapsAreSent do
  use ExUnit.Case

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.Testing.{Pipeline, Sink, Source}

  defmodule SourceWhichDoesNotSendCaps do
    use Membrane.Source

    def_output_pad :output, accepted_format: _any, mode: :pull

    @impl true
    def handle_init(_ctx, _options) do
      {:ok, %{}}
    end

    @impl true
    def handle_demand(_pad, _size, _unit, _ctx, state) do
      {:ok, state}
    end

    @impl true
    def handle_parent_notification(:send_buffer, _ctx, state) do
      {{:ok, [buffer: {:output, %Membrane.Buffer{payload: "Something"}}]}, state}
    end

    @impl true
    def handle_parent_notification({:send_your_pid, requester_pid}, _ctx, state) do
      send(requester_pid, {:my_pid, self()})
      {:ok, state}
    end
  end

  test "if pipeline crashes when the caps are not sent before the first buffer" do
    links = [
      child(:source, SourceWhichDoesNotSendCaps)
      |> child(:sink, Sink)
    ]

    options = [
      structure: links
    ]

    pipeline = Pipeline.start_supervised!(options)
    Pipeline.message_child(pipeline, :source, {:send_your_pid, self()})

    source_pid =
      receive do
        {:my_pid, pid} -> pid
      end

    source_ref = Process.monitor(source_pid)
    assert_pipeline_play(pipeline)
    Pipeline.message_child(pipeline, :source, :send_buffer)
    assert_receive {:DOWN, ^source_ref, :process, ^source_pid, {reason, _stack_trace}}
    assert %Membrane.ElementError{message: action_error_msg} = reason
    assert action_error_msg =~ ~r/buffer.*caps.*not.*sent/
  end

  test "if pipeline works properly when caps are sent before the first buffer" do
    links = [
      child(:source, Source)
      |> child(:sink, Sink)
    ]

    options = [
      structure: links
    ]

    pipeline = Pipeline.start_supervised!(options)
    ref = Process.monitor(pipeline)
    assert_start_of_stream(pipeline, :sink)
    refute_receive {:DOWN, ^ref, :process, ^pipeline, {:shutdown, :child_crash}}
  end
end
