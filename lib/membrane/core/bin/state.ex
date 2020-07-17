defmodule Membrane.Core.Bin.State do
  @moduledoc false

  # Structure representing state of a bin. It is a part of the private API.
  # It does not represent state of bins you construct, it's a state used
  # internally in Membrane.

  alias Membrane.{Child, Clock, Sync}
  alias Membrane.Core
  alias Core.{Playback, Timer}
  alias Core.Child.PadModel
  alias Core.Bin.LinkingBuffer
  alias Core.Parent.ChildrenModel
  use Bunch
  use Bunch.Access

  @type t :: %__MODULE__{
          internal_state: internal_state_t() | nil,
          playback: Playback.t(),
          module: module,
          children: ChildrenModel.children_t(),
          name: Membrane.Bin.name_t() | nil,
          bin_options: any | nil,
          pads: PadModel.pads_t() | nil,
          watcher: pid | nil,
          controlling_pid: pid | nil,
          linking_buffer: LinkingBuffer.t(),
          clock_provider: %{
            clock: Clock.t() | nil,
            provider: Child.name_t() | nil,
            choice: :auto | :manual
          },
          clock_proxy: Clock.t(),
          synchronization: %{
            timers: %{Timer.id_t() => Timer.t()},
            parent_clock: Clock.t(),
            latency: non_neg_integer(),
            stream_sync: Sync.t(),
            clock: Clock.t() | nil
          },
          children_log_metadata: Keyword.t()
        }

  @type internal_state_t :: map | struct

  @enforce_keys [:module, :clock_proxy]
  defstruct @enforce_keys ++
              [
                internal_state: nil,
                playback: %Playback{},
                children: %{},
                name: nil,
                bin_options: nil,
                pads: nil,
                watcher: nil,
                controlling_pid: nil,
                linking_buffer: LinkingBuffer.new(),
                clock_provider: %{clock: nil, provider: nil, choice: :auto},
                synchronization: %{},
                children_log_metadata: []
              ]
end
