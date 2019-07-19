defmodule Membrane.Support.ChildRemovalTest.Pipeline do
  @moduledoc false
  use Membrane.Pipeline

  @impl true
  def handle_init(opts) do
    children = [
      source: opts.source,
      filter1: opts.filter1,
      filter2: opts.filter2,
      sink: opts.sink
    ]

    links = %{
      {:source, :output} => {:filter1, :input, buffer: [preferred_size: 10]},
      {:filter1, :output} => {:filter2, :input, buffer: [preferred_size: 10]},
      {:filter2, :output} => {:sink, :input, buffer: [preferred_size: 10]}
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

  def handle_other({:remove_child, name}, state) do
    {{:ok, remove_child: name}, state}
  end

  @impl true
  def handle_prepared_to_playing(%{target: target} = state) do
    send(target, :playing)
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_stopped(%{target: t} = state) do
    send(t, :pipeline_stopped)
    {:ok, state}
  end
end
