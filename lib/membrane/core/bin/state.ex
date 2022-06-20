defmodule Membrane.Core.Bin.State do
  @moduledoc false

  # Structure representing state of a bin. It is a part of the private API.
  # It does not represent state of bins you construct, it's a state used
  # internally in Membrane.

  use Bunch
  use Bunch.Access

  alias Membrane.{Child, Clock, PlaybackState, Sync}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Parent.ChildLifeController.LinkHandler
  alias Membrane.Core.Parent.{ChildrenModel, CrashGroup, Link}
  alias Membrane.Core.{Playback, Timer}

  @type t :: %__MODULE__{
          internal_state: Membrane.Bin.state_t() | nil,
          playback: Playback.t(),
          module: module,
          children: ChildrenModel.children_t(),
          delayed_playback_change: PlaybackState.t() | nil,
          name: Membrane.Bin.name_t() | nil,
          pads_info: PadModel.pads_info_t() | nil,
          pads_data: PadModel.pads_data_t() | nil,
          parent_pid: pid,
          links: [Link.t()],
          crash_groups: %{CrashGroup.name_t() => CrashGroup.t()},
          synchronization: %{
            timers: %{Timer.id_t() => Timer.t()},
            parent_clock: Clock.t(),
            latency: non_neg_integer(),
            stream_sync: Sync.t(),
            clock: Clock.t() | nil,
            clock_proxy: Clock.t(),
            clock_provider: %{
              clock: Clock.t() | nil,
              provider: Child.name_t() | nil,
              choice: :auto | :manual
            }
          },
          children_log_metadata: Keyword.t(),
          pending_specs: LinkHandler.pending_specs_t()
        }

  @enforce_keys [:module, :synchronization, :children_supervisor]
  defstruct @enforce_keys ++
              [
                internal_state: nil,
                playback: %Playback{},
                children: %{},
                delayed_playback_change: nil,
                name: nil,
                pads_info: nil,
                pads_data: nil,
                parent_pid: nil,
                crash_groups: %{},
                children_log_metadata: [],
                links: [],
                pending_specs: %{},
                status: :initializing,
                play_request?: false,
                terminating?: false
              ]
end
