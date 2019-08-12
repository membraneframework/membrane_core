defmodule Membrane.Core.Element.State do
  @moduledoc false
  # Structure representing state of an Core.Element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Membrane.Log, tags: :core
  alias Membrane.{Clock, Core, Element}
  alias Core.{Playback, Playbackable, Timer}
  alias Core.Element.{PadModel, PadSpecHandler, PlaybackBuffer}
  alias Element.Pad
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
          playback: Playback.t(),
          playback_buffer: PlaybackBuffer.t(),
          delayed_demands: %{{Pad.ref_t(), :supply | :redemand} => :sync | :async},
          timers: %{Timer.id_t() => Timer.t()},
          terminating: boolean | :ready
        }

  defstruct [
    :module,
    :type,
    :name,
    :internal_state,
    :pads,
    :watcher,
    :controlling_pid,
    :playback,
    :playback_buffer,
    :delayed_demands,
    :timers,
    :pipeline_clock,
    :clock,
    :stream_sync,
    :latency,
    :terminating
  ]

  defimpl Playbackable, for: __MODULE__ do
    use Playbackable.Default
    def get_controlling_pid(%ThisModule{controlling_pid: pid}), do: pid
  end

  @doc """
  Initializes new state.
  """
  @spec new(%{module: module, name: Element.name_t(), clock: Clock.t()}) :: t
  def new(options) do
    %__MODULE__{
      module: options.module,
      type: apply(options.module, :membrane_element_type, []),
      name: options.name,
      internal_state: nil,
      pads: nil,
      watcher: nil,
      controlling_pid: nil,
      playback: %Playback{},
      playback_buffer: PlaybackBuffer.new(),
      delayed_demands: %{},
      timers: %{},
      pipeline_clock: options.clock,
      clock: nil,
      stream_sync: options.sync,
      latency: 0,
      terminating: false
    }
    |> PadSpecHandler.init_pads()
  end
end
