defmodule Membrane.Core.Element.State do
  @moduledoc false

  # Structure representing state of an Core.Element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Membrane.Log, tags: :core
  alias Membrane.{Clock, Core, Element, Pad, Sync}
  alias Core.{Playback, Playbackable, Timer}
  alias Core.Child.{PadModel, PadSpecHandler}
  alias Core.Element.PlaybackBuffer
  alias Bunch.Type
  alias __MODULE__, as: ThisModule
  require Pad
  use Bunch.Access

  @type stateful_t(value) :: Type.stateful_t(value, t)
  @type stateful_try_t :: Type.stateful_try_t(t)
  @type stateful_try_t(value) :: Type.stateful_try_t(value, t)

  @type t :: %__MODULE__{
          module: module,
          type: Element.type_t(),
          name: Element.name_t(),
          internal_state: Element.state_t() | nil,
          pads: PadModel.pads_t() | nil,
          watcher: pid | nil,
          controlling_pid: pid | nil,
          parent_monitor: reference() | nil,
          playback: Playback.t(),
          playback_buffer: PlaybackBuffer.t(),
          delayed_demands: %{{Pad.ref_t(), :supply | :redemand} => :sync | :async},
          synchronization: %{
            timers: %{Timer.id_t() => Timer.t()},
            parent_clock: Clock.t(),
            latency: non_neg_integer(),
            stream_sync: Sync.t(),
            clock: Clock.t() | nil
          }
        }

  defstruct [
    :module,
    :type,
    :name,
    :internal_state,
    :pads,
    :watcher,
    :controlling_pid,
    :parent_monitor,
    :playback,
    :playback_buffer,
    :delayed_demands,
    :synchronization
  ]

  @doc """
  Initializes new state.
  """
  @spec new(%{
          module: module,
          name: Element.name_t(),
          clock: Clock.t(),
          sync: Sync.t(),
          parent_monitor: reference()
        }) :: t
  def new(options) do
    %__MODULE__{
      module: options.module,
      type: apply(options.module, :membrane_element_type, []),
      name: options.name,
      internal_state: nil,
      pads: nil,
      watcher: nil,
      controlling_pid: nil,
      parent_monitor: options[:parent_monitor],
      playback: %Playback{},
      playback_buffer: PlaybackBuffer.new(),
      delayed_demands: %{},
      synchronization: %{
        parent_clock: options.clock,
        timers: %{},
        clock: nil,
        stream_sync: options.sync,
        latency: 0
      }
    }
    |> PadSpecHandler.init_pads()
  end
end
