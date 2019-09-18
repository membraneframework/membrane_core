defmodule Membrane.Support.Sync.Pipeline do
  use Membrane.Pipeline
  alias Membrane.Testing.{Source, Sink}

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

    links = %{
      {:source_a, :output} => {:sink_a, :input},
      {:source_b, :output} => {:sink_b, :input}
    }

    %Membrane.Pipeline.Spec{
      children: children,
      links: links,
      stream_sync: :sinks
    }
  end

  @impl true
  def handle_init(spec) do
    {{:ok, spec: spec}, %{}}
  end
end
