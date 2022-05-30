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

    links = [
      link(:source)
      |> via_in(:input, target_queue_size: 50)
      |> to(:filter)
      |> via_in(:input, target_queue_size: 50)
      |> to(:sink)
    ]

    spec = %Membrane.ParentSpec{
      children: children,
      links: links
    }

    {{:ok, spec: spec, playback: :playing}, %{target: opts.target}}
  end

  @impl true
  def handle_info({:child_msg, name, msg}, _ctx, state) do
    {{:ok, notify_child: {name, msg}}, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, %{target: target} = state) do
    send(target, :playing)
    {:ok, state}
  end
end
