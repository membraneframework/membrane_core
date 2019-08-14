defmodule Membrane.Core.Bin.State do
  @moduledoc false
  # Structure representing state of a bin. It is a part of the private API.
  # It does not represent state of bins you construct, it's a state used
  # internally in Membrane.

  alias Membrane.Core.{Playback, Playbackable, PadModel}
  alias Membrane.Element
  alias Membrane.Core.Bin.LinkingBuffer
  alias __MODULE__, as: ThisModule
  use Bunch
  use Bunch.Access

  @type t :: %__MODULE__{
          internal_state: internal_state_t | nil,
          playback: Playback.t(),
          module: module,
          children: children_t,
          pending_pids: MapSet.t(pid),
          terminating?: boolean,
          name: Bin.name_t(),
          bin_options: any,
          pads: PadModel.pads_t() | nil,
          watcher: pid,
          controlling_pid: pid,
          linking_buffer: LinkingBuffer.t()
        }

  @type internal_state_t :: map | struct
  @type child_t :: {Element.name_t(), pid}
  @type children_t :: %{Element.name_t() => pid}

  defstruct internal_state: nil,
            playback: %Playback{},
            module: nil,
            children: %{},
            pending_pids: MapSet.new(),
            terminating?: false,
            name: nil,
            bin_options: nil,
            pads: nil,
            watcher: nil,
            controlling_pid: nil,
            linking_buffer: LinkingBuffer.new()

  defimpl Playbackable, for: __MODULE__ do
    use Playbackable.Default
    def get_controlling_pid(%ThisModule{controlling_pid: pid}), do: pid
  end

  defimpl Membrane.Core.Parent.State, for: __MODULE__ do
    use Membrane.Core.Parent.State.Default
  end
end
