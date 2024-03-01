defmodule Membrane.Core.Pipeline.State do
  @moduledoc false

  # Structure representing state of a pipeline. It is a part of the private API.
  # It does not represent state of pipelines you construct, it's a state used
  # internally in Membrane.

  use Bunch
  use Bunch.Access

  alias Membrane.Child
  alias Membrane.Core.Parent.{ChildLifeController, ChildrenModel, CrashGroup, Link}
  alias Membrane.Core.Timer

  @type t :: %__MODULE__{
          module: module,
          playback: Membrane.Playback.t(),
          internal_state: Membrane.Pipeline.state() | nil,
          children: ChildrenModel.children(),
          links: %{Link.id() => Link.t()},
          crash_groups: %{CrashGroup.name() => CrashGroup.t()},
          pending_specs: ChildLifeController.pending_specs(),
          synchronization: %{
            timers: %{Timer.id() => Timer.t()},
            clock_provider: %{
              clock: Membrane.Clock.t() | nil,
              provider: Child.name() | nil
            },
            clock_proxy: Membrane.Clock.t()
          },
          initialized?: boolean(),
          terminating?: boolean(),
          resource_guard: Membrane.ResourceGuard.t(),
          setup_incomplete?: boolean(),
          handling_action?: boolean(),
          stalker: Membrane.Core.Stalker.t(),
          subprocess_supervisor: pid(),
          awaiting_setup_completition?: boolean()
        }

  # READ THIS BEFORE ADDING NEW FIELD!!!

  # Fields of this structure will be inspected in the same order, in which they occur in the
  # list passed to `defstruct`. Take a look at lib/membrane/core/inspect.ex to get more info.
  # If you want to add a new field to the state, place it at the spot corresponding to its
  # importance and possibly near other related fields.

  defstruct module: nil,
            playback: :stopped,
            internal_state: nil,
            children: %{},
            links: %{},
            crash_groups: %{},
            pending_specs: %{},
            synchronization: nil,
            initialized?: false,
            terminating?: false,
            setup_incomplete?: false,
            handling_action?: false,
            stalker: nil,
            resource_guard: nil,
            subprocess_supervisor: nil,
            awaiting_setup_completition?: false
end
