defmodule Membrane.Core.Pipeline.State do
  @moduledoc false

  # Structure representing state of a pipeline. It is a part of the private API.
  # It does not represent state of pipelines you construct, it's a state used
  # internally in Membrane.

  use Bunch
  use Bunch.Access

  alias Membrane.Child
  alias Membrane.Core.Parent.{ChildrenModel, Link}
  alias Membrane.Core.{Playback, Timer}
  alias Membrane.Core.Parent.CrashGroup

  @type t :: %__MODULE__{
          internal_state: Membrane.Pipeline.state_t(),
          playback: Playback.t(),
          module: module,
          children: ChildrenModel.children_t(),
          crash_groups: %{CrashGroup.name_t() => CrashGroup.t()},
          links: [Link.t()],
          synchronization: %{
            timers: %{Timer.id_t() => Timer.t()},
            clock_provider: %{
              clock: Membrane.Clock.t() | nil,
              provider: Child.name_t() | nil,
              choice: :auto | :manual
            },
            clock_proxy: Membrane.Clock.t()
          },
          children_log_metadata: Keyword.t()
        }

  @enforce_keys [:module, :synchronization]
  defstruct @enforce_keys ++
              [
                internal_state: nil,
                children: %{},
                crash_groups: %{},
                links: [],
                pending_links: %{},
                playback: %Playback{},
                children_log_metadata: []
              ]
end
