defmodule Membrane.Core.Pipeline.State do
  @moduledoc false

  # Structure representing state of a pipeline. It is a part of the private API.
  # It does not represent state of pipelines you construct, it's a state used
  # internally in Membrane.

  alias Membrane.Child
  alias Membrane.Core.{Playback, Playbackable}
  alias Membrane.{Clock, Sync}
  use Bunch

  @derive Playbackable

  @type t :: %__MODULE__{
          internal_state: internal_state_t | nil,
          playback: Playback.t(),
          module: module,
          children: children_t,
          pending_pids: MapSet.t(pid),
          clock_provider: %{
            clock: Clock.t() | nil,
            provider: Child.name_t() | nil,
            choice: :auto | :manual
          },
          clock_proxy: Clock.t()
        }

  @type internal_state_t :: map | struct
  @type child_data_t :: %{pid: pid, clock: Clock.t(), sync: Sync.t()}
  @type children_t :: %{Child.name_t() => child_data_t}

  @enforce_keys [:module, :clock_proxy]
  defstruct @enforce_keys ++
              [
                internal_state: nil,
                children: %{},
                playback: %Playback{},
                pending_pids: MapSet.new(),
                clock_provider: %{clock: nil, provider: nil, choice: :auto}
              ]
end
