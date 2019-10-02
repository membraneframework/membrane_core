defmodule Membrane.Core.Element.StateSpec do
  use ESpec, async: true
  alias Membrane.Support.Element.TrivialFilter
  alias Membrane.Core.{PadSpecHandler, Playback}
  alias Membrane.Core.Element.PlaybackBuffer
  alias Membrane.Sync

  describe "new/1" do
    it "should create proper state" do
      state =
        described_module().new(%{
          module: TrivialFilter,
          name: :name,
          clock: nil,
          sync: Sync.no_sync()
        })

      expect(state)
      |> to(
        eq struct(
             described_module(),
             module: TrivialFilter,
             type: :filter,
             name: :name,
             internal_state: nil,
             pads: PadSpecHandler.init_pads(state).pads,
             watcher: nil,
             controlling_pid: nil,
             playback: %Playback{},
             playback_buffer: PlaybackBuffer.new(),
             delayed_demands: %{},
             synchronization: %{
               timers: %{},
               clock: nil,
               pipeline_clock: nil,
               latency: 0,
               stream_sync: Sync.no_sync()
             },
             terminating: false
           )
      )
    end
  end
end
