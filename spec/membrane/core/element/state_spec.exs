defmodule Membrane.Core.Element.StateSpec do
  use ESpec, async: true

  alias Membrane.Core.Child.PadSpecHandler
  alias Membrane.Core.Element.PlaybackBuffer
  alias Membrane.Core.Playback
  alias Membrane.Support.Element.TrivialFilter
  alias Membrane.Sync

  describe "new/1" do
    it "should create proper state" do
      state =
        described_module().new(%{
          module: TrivialFilter,
          name: :name,
          parent_clock: nil,
          sync: Sync.no_sync(),
          parent: self()
        })

      expect(state)
      |> to(
        eq struct(
             described_module(),
             module: TrivialFilter,
             type: :filter,
             name: :name,
             internal_state: nil,
             playback: %Playback{},
             playback_buffer: PlaybackBuffer.new(),
             supplying_demand?: false,
             delayed_demands: MapSet.new(),
             parent_pid: self(),
             synchronization: %{
               timers: %{},
               clock: nil,
               parent_clock: nil,
               latency: 0,
               stream_sync: Sync.no_sync()
             },
             terminating: false
           )
           |> PadSpecHandler.init_pads()
      )
    end
  end
end
