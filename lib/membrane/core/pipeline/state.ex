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
          children: ChildrenModel.children_t(),
          crash_groups: %{CrashGroup.name_t() => CrashGroup.t()},
          links: %{Link.id() => Link.t()},
          synchronization: %{
            timers: %{Timer.id_t() => Timer.t()},
            clock_provider: %{
              clock: Membrane.Clock.t() | nil,
              provider: Child.name_t() | nil,
              choice: :auto | :manual
            },
            clock_proxy: Membrane.Clock.t()
          },
          playback: Membrane.Playback.t(),
          initialized?: boolean(),
          playing_requested?: boolean(),
          terminating?: boolean(),
          resource_guard: Membrane.ResourceGuard.t()
        }

  @enforce_keys [:module, :synchronization, :subprocess_supervisor, :resource_guard]
  defstruct @enforce_keys ++
              [
                internal_state: nil,
                children: %{},
                crash_groups: %{},
                links: %{},
                pending_specs: %{},
                playback: :stopped,
                initialized?: false,
                playing_requested?: false,
                terminating?: false
              ]
end
