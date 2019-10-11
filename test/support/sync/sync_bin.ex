defmodule Membrane.Support.Sync.SyncBin do
  use Membrane.Bin
  alias Membrane.Support.Sync

  @impl true
  def handle_init(_) do
    {{:ok, spec: Sync.Pipeline.default_spec()}, %{}}
  end

  @impl true
  def handle_element_start_of_stream({child, _pad}, state) do
    {{:ok, notify: {:start_of_stream, child}}, state}
  end
end
