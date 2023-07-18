defmodule PipelineSynchronousCallTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions

  alias Membrane.Pipeline

  @msg "Some message"
  defmodule TestPipeline do
    use Membrane.Pipeline
    @impl true
    def handle_init(_ctx, result) do
      result || {[], %{}}
    end

    @impl true
    def handle_child_notification(notification, child, _ctx, state) do
      {[], Map.put(state, :notification, {notification, child})}
    end

    @impl true
    def handle_info({{:please_reply, msg}, pid}, _ctx, state) do
      {[reply_to: {pid, msg}], state}
    end

    @impl true
    def handle_call({:instant_reply, msg}, _ctx, state) do
      {[reply: msg], state}
    end

    @impl true
    def handle_call({:postponed_reply, msg}, ctx, state) do
      send(self(), {{:please_reply, msg}, ctx.from})
      {[], state}
    end
  end

  test "Pipeline should be able to reply to a call with :reply_to action" do
    pid = Membrane.Testing.Pipeline.start_link_supervised!(module: TestPipeline)

    reply = Pipeline.call(pid, {:postponed_reply, @msg})
    assert reply == @msg

    Pipeline.terminate(pid)
  end

  test "Pipeline should be able to reply to a call with :reply action" do
    pid = Membrane.Testing.Pipeline.start_link_supervised!(module: TestPipeline)

    reply = Pipeline.call(pid, {:instant_reply, @msg})
    assert reply == @msg

    Pipeline.terminate(pid)
  end

  defmodule PipelineSpawningChildrenOnCall do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, _options) do
      {[], %{}}
    end

    @impl true
    def handle_call(:spawn_children, _ctx, state) do
      spec =
        child(:source, %Membrane.Testing.Source{output: [1, 2, 3]})
        |> child(:sink, Membrane.Testing.Sink)

      {[spec: spec, reply: nil], state}
    end
  end

  test "Pipeline should be able to perform actions before replying on handle_call" do
    {:ok, _supervisor, pipeline_pid} =
      Membrane.Testing.Pipeline.start(module: PipelineSpawningChildrenOnCall)

    Pipeline.call(pipeline_pid, :spawn_children)
    assert_end_of_stream(pipeline_pid, :sink)

    Pipeline.terminate(pipeline_pid)
  end
end
