defmodule Membrane.Integration.PipelineSupervisorTest do
  use ExUnit.Case, async: true
  alias Membrane.Testing

  defmodule HelperPipeline do
    use Membrane.Pipeline
    alias Membrane.Testing

    @impl true
    def handle_init(_ctx, _opts) do
      spec = child(Testing.Source) |> child(Testing.Sink)
      {[spec: spec], %{}}
    end

    @impl true
    def handle_info(:raise, _ctx, _state), do: raise("some message")
  end

  test "supervisor dies when pipeline raises" do
    {:ok, supervisor, pipeline} = Membrane.Pipeline.start(HelperPipeline)
    ref = Process.monitor(supervisor)

    Process.sleep(500)
    send(pipeline, :raise)

    assert_receive {:DOWN, ^ref, :process, _pid, {%{message: "some message"}, _stacktrace}}
  end
end
