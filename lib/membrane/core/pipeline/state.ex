defmodule Membrane.Core.Pipeline.State do
  @moduledoc false

  # Structure representing state of a pipeline. It is a part of the private API.
  # It does not represent state of pipelines you construct, it's a state used
  # internally in Membrane.

  use Bunch
  use Bunch.Access

  alias Membrane.Child
  alias Membrane.Core.Parent.{ChildrenModel, CrashGroup, Link}
  alias Membrane.Core.Timer

  @type t :: %__MODULE__{
          internal_state: Membrane.Pipeline.state() | nil,
          module: module,
          children: ChildrenModel.children(),
          crash_groups: %{CrashGroup.name() => CrashGroup.t()},
          links: %{Link.id() => Link.t()},
          synchronization: %{
            timers: %{Timer.id() => Timer.t()},
            clock_provider: %{
              clock: Membrane.Clock.t() | nil,
              provider: Child.name() | nil,
              choice: :auto | :manual
            },
            clock_proxy: Membrane.Clock.t()
          },
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
                crash_groups: %{},
                links: %{},
                pending_specs: %{},
                playback: :stopped,
                initialized?: false,
                terminating?: false,
                setup_incomplete?: false,
                handling_action?: false
              ]
end
