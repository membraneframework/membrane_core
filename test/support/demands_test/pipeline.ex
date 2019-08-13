defmodule Membrane.Support.DemandsTest.Pipeline do
  @moduledoc false
  use Membrane.Pipeline
  alias Membrane.Spec

  @impl true
  def handle_init(opts) do
    children = [
      source: opts.source,
      filter: opts.filter,
      sink: opts.sink
    ]

    links = %{
      {:source, :output} => {:filter, :input, buffer: [preferred_size: 50]},
      {:filter, :output} => {:sink, :input, buffer: [preferred_size: 50]}
    }

    spec = %Spec{
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
