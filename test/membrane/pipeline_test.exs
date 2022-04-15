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
    def handle_other(message, _ctx, state) do
      {:ok, Map.put(state, :other, message)}
    end

    @impl true
    def handle_call(_message, _ctx, state) do
      {:ok, state}
    end
  end

  test "Pipeline should be able to be called synchronously" do
    {:ok, pid} = Membrane.Testing.Pipeline.start_link(%Membrane.Testing.Pipeline.Options{module: TestPipeline})
    Pipeline.call(pid, "Some message")

  end
end
