defmodule Membrane.Support.Sync.SyncBin do
  @moduledoc false
  use Membrane.Bin

  alias Membrane.Support.Sync

  @impl true
  def handle_init(_options) do
    {{:ok, spec: Sync.Pipeline.default_spec()}, %{}}
  end

  @impl true
  def handle_element_start_of_stream(child, _pad, _ctx, state) do
    {{:ok, notify_parent: {:start_of_stream, child}}, state}
  end
end
