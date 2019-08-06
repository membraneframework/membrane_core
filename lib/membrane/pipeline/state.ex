defmodule Membrane.Pipeline.State do
  @moduledoc false
  # Structure representing state of a pipeline. It is a part of the private API.
  # It does not represent state of pipelines you construct, it's a state used
  # internally in Membrane.

  alias Membrane.Core.{Playback, Playbackable}
  alias Membrane.Element
  alias Bunch.Type
  use Bunch

  @derive Playbackable

  @type t :: %__MODULE__{
          internal_state: internal_state_t | nil,
          playback: Playback.t(),
          module: module,
          children: children_t,
          pending_pids: MapSet.t(pid),
          terminating?: boolean
        }

  @type internal_state_t :: map | struct
  @type child_t :: {Element.name_t(), pid}
  @type children_t :: %{Element.name_t() => pid}

  defstruct internal_state: nil,
            module: nil,
            children: %{},
            playback: %Playback{},
            pending_pids: MapSet.new(),
            terminating?: false

  defimpl Membrane.Core.ParentState, for: __MODULE__ do
    use Membrane.Core.ParentState.Default
  end
end
