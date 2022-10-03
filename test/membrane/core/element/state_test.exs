defmodule Membrane.Core.Element.StateTest do
  use ExUnit.Case, async: true

  alias Membrane.Core.Element.State
  alias Membrane.Support.Elements.TrivialFilter
  alias Membrane.Sync

  test "State.new/1 create a proper state structure" do
    state =
      State.new(%{
        module: TrivialFilter,
        name: :name,
        parent_clock: nil,
        sync: Sync.no_sync(),
        parent: self(),
        resource_guard: self(),
        children_supervisor: self()
      })

    assert %State{
             module: TrivialFilter,
             type: :filter,
             name: :name,
             internal_state: nil,
             playback: :stopped,
             supplying_demand?: false,
             delayed_demands: delayed_demands,
             parent_pid: parent_pid,
             synchronization: %{
               timers: %{},
               clock: nil,
               parent_clock: nil,
               latency: 0,
               stream_sync: stream_sync
             },
             terminating?: false
           } = state

    assert delayed_demands == MapSet.new()
    assert parent_pid == self()
    assert stream_sync == Sync.no_sync()
  end
end
