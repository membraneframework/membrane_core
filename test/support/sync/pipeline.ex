defmodule Membrane.Support.Sync.Pipeline do
  @moduledoc false
  use Membrane.Pipeline

  alias Membrane.Testing.{Sink, Source}

  @spec default_spec() :: Membrane.ParentSpec.t()
  def default_spec() do
    demand_generator = fn time, _size ->
      Process.sleep(time)
      buffer = %Membrane.Buffer{payload: "b"}
      {[buffer: {:output, buffer}], time}
    end

    children = [
      source_a: %Source{output: ["a"]},
      sink_a: %Sink{},
      source_b: %Source{output: {200, demand_generator}},
      sink_b: %Sink{}
    ]

    links = [
      link(:source_a) |> to(:sink_a),
      link(:source_b) |> to(:sink_b)
    ]

    %Membrane.ParentSpec{
      children: children,
      links: links,
      stream_sync: :sinks
    }
  end

  @impl true
  def handle_init(spec) do
    {{:ok, spec: spec, playback: :playing}, %{}}
  end

  @impl true
  def handle_info({:spawn_children, spec}, _ctx, state) do
    {{:ok, spec: spec}, state}
  end
end
