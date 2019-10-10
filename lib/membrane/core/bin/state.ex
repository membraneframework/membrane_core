defmodule Membrane.Core.Bin.State do
  @moduledoc false
  # Structure representing state of a bin. It is a part of the private API.
  # It does not represent state of bins you construct, it's a state used
  # internally in Membrane.

  alias Membrane.{Child, Clock, Parent, Sync}
  alias Membrane.Core
  alias Core.{Bin, Playback, Playbackable, PadModel, Timer}
  alias Core.Bin.LinkingBuffer
  alias __MODULE__, as: ThisModule
  use Bunch
  use Bunch.Access

  @type t :: %__MODULE__{
          internal_state: Parent.internal_state_t() | nil,
          playback: Playback.t(),
          module: module,
          children: Parent.children_t(),
          pending_pids: MapSet.t(pid),
          terminating?: boolean,
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
          handlers: Core.Parent.MessageDispatcher.handlers(),
          synchronization: %{
            timers: %{Timer.id_t() => Timer.t()},
            parent_clock: Clock.t(),
            latency: non_neg_integer(),
            stream_sync: Sync.t(),
            clock: Clock.t() | nil
          }
        }

  @type internal_state_t :: map | struct

  @enforce_keys [:module, :clock_proxy]
  defstruct @enforce_keys ++
              [
                internal_state: nil,
                playback: %Playback{},
                children: %{},
                pending_pids: MapSet.new(),
                terminating?: false,
                name: nil,
                bin_options: nil,
                pads: nil,
                watcher: nil,
                controlling_pid: nil,
                linking_buffer: LinkingBuffer.new(),
                clock_provider: %{clock: nil, provider: nil, choice: :auto},
                handlers: %{
                  action_handler: Bin.ActionHandler,
                  playback_controller: Core.Parent.LifecycleController,
                  spec_controller: Bin.SpecController
                },
                synchronization: %{}
              ]

  defimpl Playbackable, for: __MODULE__ do
    use Playbackable.Default
    def get_controlling_pid(%ThisModule{controlling_pid: pid}), do: pid
  end
end
