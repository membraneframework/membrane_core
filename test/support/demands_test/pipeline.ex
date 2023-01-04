defmodule Membrane.Support.DemandsTest.Pipeline do
  @moduledoc false
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    children = [
      source: opts.source,
      filter: opts.filter,
      sink: opts.sink
    ]

    links = [
      get_child(:source)
      |> via_in(:input, target_queue_size: 50)
      |> get_child(:filter)
      |> via_in(:input, target_queue_size: 50)
      |> get_child(:sink)
    ]

    spec = children ++ links

    {[spec: spec], %{target: opts.target}}
  end

  @impl true
  def handle_info({:child_msg, name, msg}, _ctx, state) do
    {[notify_child: {name, msg}], state}
  end

  @impl true
  def handle_playing(_ctx, %{target: target} = state) do
    send(target, :playing)
    {[], state}
  end
end
