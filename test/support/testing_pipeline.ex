defmodule Membrane.Integration.TestingPipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(opts) do
    children = [
      source: opts.source,
      filter: opts.filter,
      sink: opts.sink
    ]

    links = %{
      {:source, :source} => {:filter, :sink, pull_buffer: [preferred_size: 50]},
      {:filter, :source} => {:sink, :sink, pull_buffer: [preferred_size: 50]}
    }

    spec = %Pipeline.Spec{
      children: children,
      links: links
    }

    {{:ok, spec}, %{target: opts.target}}
  end

  @impl true
  def handle_other({:child_msg, name, msg}, state) do
    {{:ok, forward: {name, msg}}, state}
  end

  @impl true
  def handle_prepared_to_playing(%{target: target} = state) do
    send(target, :playing)
    {:ok, state}
  end
end
