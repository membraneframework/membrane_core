defmodule Membrane.Core.Bin.State do
  @moduledoc false

  # Structure representing state of a bin. It is a part of the private API.
  # It does not represent state of bins you construct, it's a state used
  # internally in Membrane.

  use Bunch
  use Bunch.Access

  alias Membrane.{Child, Clock, Sync}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Parent.ChildLifeController
  alias Membrane.Core.Parent.{ChildrenModel, CrashGroup, Link}
  alias Membrane.Core.Timer

  @type t :: %__MODULE__{
          internal_state: Membrane.Bin.state() | nil,
          module: module,
          children: ChildrenModel.children(),
          subprocess_supervisor: pid(),
          name: Membrane.Bin.name() | nil,
          pads_info: PadModel.pads_info() | nil,
          pads_data: PadModel.pads_data() | nil,
          parent_pid: pid,
          links: %{Link.id() => Link.t()},
          crash_groups: %{CrashGroup.name() => CrashGroup.t()},
          synchronization: %{
            timers: %{Timer.id() => Timer.t()},
            parent_clock: Clock.t(),
            latency: Membrane.Time.non_neg(),
            stream_sync: Sync.t(),
            clock: Clock.t() | nil,
            clock_proxy: Clock.t(),
            clock_provider: %{
              clock: Clock.t() | nil,
              provider: Child.name() | nil,
              choice: :auto | :manual
            }
          },
          children_log_metadata: Keyword.t(),
          pending_specs: ChildLifeController.pending_specs(),
          playback: Membrane.Playback.t(),
          initialized?: boolean(),
          terminating?: boolean(),
          resource_guard: Membrane.ResourceGuard.t(),
          setup_incomplete?: boolean(),
          handling_action?: boolean(),
          stalker: Membrane.Core.Stalker.t()
        }

  @enforce_keys [:module, :synchronization, :subprocess_supervisor, :resource_guard, :stalker]
  defstruct @enforce_keys ++
              [
                internal_state: nil,
                children: %{},
                name: nil,
                pads_info: nil,
                pads_data: nil,
                parent_pid: nil,
                crash_groups: %{},
                children_log_metadata: [],
                links: %{},
                pending_specs: %{},
                playback: :stopped,
                initialized?: false,
                terminating?: false,
                setup_incomplete?: false,
                handling_action?: false
              ]
end
