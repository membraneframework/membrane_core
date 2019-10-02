defmodule Membrane.Support.DemandsTest.Pipeline do
  @moduledoc false
  use Membrane.Pipeline

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

    spec = %Membrane.Spec{
      children: children,
      links: links
    }

    {{:ok, spec: spec}, %{target: opts.target}}
  end

  @impl true
  def handle_other({:child_msg, name, msg}, state) do
    {{:ok, forward: {name, msg}}, state}
  end


  @impl true
  def handle_stopped_to_prepared(%{target: target} = state) do
    IO.puts "handle_stopped_to_prepared is called"
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(%{target: target} = state) do
    IO.puts "handle_prepared_to_playing is called"
    send(target, :playing)
    {:ok, state}
  end
end
