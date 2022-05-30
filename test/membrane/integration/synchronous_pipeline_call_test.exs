defmodule PipelineSynchronousCallTest do
  use ExUnit.Case, async: false

  alias Membrane.Pipeline

  @msg "Some message"
  defmodule TestPipeline do
    use Membrane.Pipeline
    @impl true
    def handle_init(result) do
      result || {:ok, %{}}
    end

    @impl true
    def handle_notification(notification, child, _ctx, state) do
      {:ok, Map.put(state, :notification, {notification, child})}
    end

    @impl true
    def handle_info({{:please_reply, msg}, pid}, _ctx, state) do
      {{:ok, reply_to: {pid, msg}}, state}
    end

    @impl true
    def handle_call({:instant_reply, msg}, _ctx, state) do
      {{:ok, reply: msg}, state}
    end

    @impl true
    def handle_call({:postponed_reply, msg}, ctx, state) do
      send(self(), {{:please_reply, msg}, ctx.from})
      {:ok, state}
    end
  end

  test "Pipeline should be able to reply to a call with :reply_to action" do
    {:ok, pid} = Membrane.Testing.Pipeline.start_link(module: TestPipeline)

    reply = Pipeline.call(pid, {:postponed_reply, @msg})
    assert reply == @msg
  end

  test "Pipeline should be able to reply to a call with :reply action" do
    {:ok, pid} = Membrane.Testing.Pipeline.start_link(module: TestPipeline)

    reply = Pipeline.call(pid, {:instant_reply, @msg})
    assert reply == @msg
  end
end
