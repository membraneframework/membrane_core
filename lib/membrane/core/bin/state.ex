defmodule Membrane.Core.Bin.State do
  @moduledoc false

  # Structure representing state of a bin. It is a part of the private API.
  # It does not represent state of bins you construct, it's a state used
  # internally in Membrane.

  use Bunch
  use Bunch.Access

  alias Membrane.{Child, Clock, Pad, Sync}
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
              provider: Child.name() | nil
            }
          },
          children_log_metadata: Keyword.t(),
          pending_specs: ChildLifeController.pending_specs(),
          playback: Membrane.Playback.t(),
          initialized?: boolean(),
          terminating?: boolean(),
          resource_guard: Membrane.ResourceGuard.t(),
          setup_incomplete?: boolean(),
          stalker: Membrane.Core.Stalker.t()
        }

  # READ THIS BEFORE ADDING NEW FIELD!!!

  # Fields of this structure will be inspected in the same order, in which they occur in the
  # list passed to `defstruct`. Take a look at lib/membrane/core/inspect.ex to get more info.
  # If you want to add a new field to the state, place it at the spot corresponding to its
  # importance and possibly near other related fields. It is suggested, to keep `:pads_data`
  # as the last item in the list, because sometimes it is so big, that everything after it
  # might be truncated during the inspection.

  defstruct module: nil,
            name: nil,
            parent_pid: nil,
            playback: :stopped,
            internal_state: nil,
            pads_info: nil,
            children: %{},
            links: %{},
            crash_groups: %{},
            pending_specs: %{},
            synchronization: nil,
            initialized?: false,
            terminating?: false,
            setup_incomplete?: false,
            stalker: nil,
            resource_guard: nil,
            subprocess_supervisor: nil,
            children_log_metadata: [],
            pads_data: nil
end
