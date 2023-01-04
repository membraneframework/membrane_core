defmodule Membrane.Support.Sync.Pipeline do
  @moduledoc false
  use Membrane.Pipeline

  import Membrane.ChildrenSpec

  alias Membrane.Testing.{Sink, Source}

  @spec default_spec() :: Membrane.ChildrenSpec.t()
  def default_spec() do
    demand_generator = fn time, _size ->
      Process.sleep(time)
      buffer = %Membrane.Buffer{payload: "b"}
      {[buffer: {:output, buffer}], time}
    end

    children = [
      child(:source_a, %Source{output: ["a"]}),
      child(:sink_a, %Sink{}),
      child(:source_b, %Source{output: {200, demand_generator}}),
      child(:sink_b, %Sink{})
    ]

    links = [
      get_child(:source_a) |> get_child(:sink_a),
      get_child(:source_b) |> get_child(:sink_b)
    ]

    {
      children ++ links,
      stream_sync: :sinks
    }
  end

  @impl true
  def handle_init(_ctx, spec) do
    {[spec: spec], %{}}
  end

  @impl true
  def handle_info({:spawn_children, spec}, _ctx, state) do
    {[spec: spec], state}
  end
end
