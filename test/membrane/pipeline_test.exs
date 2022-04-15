defmodule PipelineTest do
  use ExUnit.Case, async: false

  alias Membrane.Pipeline

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
    def handle_other({:please_reply, pid}, _ctx, state) do
      Process.sleep(4000)
      {{:ok, reply_to: {pid, "HELLO"}}, state}
    end

    @impl true
    def handle_call(_message, ctx, state) do
      send(self(), {:please_reply, ctx.from})
      {:ok, state}
      # {{:ok, reply: "HELLO"}, state}
    end
  end

  test "Pipeline should be able to be called synchronously" do
    {:ok, pid} =
      Membrane.Testing.Pipeline.start_link(%Membrane.Testing.Pipeline.Options{
        module: TestPipeline
      })

    Pipeline.call(pid, "Some message")
  end
end
