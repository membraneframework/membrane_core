defmodule Membrane.Core.Bin.State do
  @moduledoc false

  # Structure representing state of a bin. It is a part of the private API.
  # It does not represent state of bins you construct, it's a state used
  # internally in Membrane.

  use Bunch
  use Bunch.Access

  alias Membrane.Core.{Playback, Timer}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Parent.Link
  alias Membrane.Core.Parent.ChildLifeController.LinkHandler
  alias Membrane.Core.Parent.ChildrenModel
  alias Membrane.{Child, Clock, Sync}
  alias Membrane.Core.Parent.CrashGroup

  @type t :: %__MODULE__{
          internal_state: Membrane.Bin.state_t() | nil,
          playback: Playback.t(),
          module: module,
          children: ChildrenModel.children_t(),
          name: Membrane.Bin.name_t() | nil,
          pads: PadModel.pads_t() | nil,
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

  @enforce_keys [:module, :synchronization]
  defstruct @enforce_keys ++
              [
                internal_state: nil,
                playback: %Playback{},
                children: %{},
                name: nil,
                pads: nil,
                parent_pid: nil,
                crash_groups: %{},
                children_log_metadata: [],
                links: [],
                pending_specs: %{}
              ]
end
