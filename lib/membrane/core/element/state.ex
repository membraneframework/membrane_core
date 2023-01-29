defmodule Membrane.Core.Element.State do
  @moduledoc false

  # Structure representing state of an Core.Element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Bunch.Access

  alias Membrane.{Clock, Element, Pad, Sync}
  alias Membrane.Core.Timer
  alias Membrane.Core.Child.{PadModel, PadSpecHandler}

  require Membrane.Pad

  @type t :: %__MODULE__{
          module: module,
          type: Element.type(),
          name: Element.name(),
          internal_state: Element.state() | nil,
          pads_info: PadModel.pads_info() | nil,
          pads_data: PadModel.pads_data() | nil,
          parent_pid: pid,
          supplying_demand?: boolean(),
          delayed_demands: MapSet.t({Pad.ref(), :supply | :redemand}),
          synchronization: %{
            timers: %{Timer.id() => Timer.t()},
            parent_clock: Clock.t(),
            latency: Membrane.Time.non_neg(),
            stream_sync: Sync.t(),
            clock: Clock.t() | nil
          },
          initialized?: boolean(),
          playback: Membrane.Playback.t(),
          playback_queue: Membrane.Core.Element.PlaybackQueue.t(),
          resource_guard: Membrane.ResourceGuard.t(),
          subprocess_supervisor: pid,
          terminating?: boolean(),
          setup_incomplete?: boolean(),
          buffers_recv: non_neg_integer(),
          buffers_sent: non_neg_integer(),
          buffers_proc_time: non_neg_integer()
        }

  defstruct [
    :module,
    :type,
    :name,
    :internal_state,
    :pads_info,
    :pads_data,
    :parent_pid,
    :supplying_demand?,
    :delayed_demands,
    :synchronization,
    :demand_size,
    :initialized?,
    :playback,
    :playback_queue,
    :resource_guard,
    :subprocess_supervisor,
    :terminating?,
    :setup_incomplete?,
    buffers_recv: 0,
    buffers_sent: 0,
    buffers_proc_time: 0
  ]

  @doc """
  Initializes new state.
  """
  @spec new(%{
          module: module,
          name: Element.name(),
          parent_clock: Clock.t(),
          sync: Sync.t(),
          parent: pid,
          resource_guard: Membrane.ResourceGuard.t(),
          subprocess_supervisor: pid()
        }) :: t
  def new(options) do
    %__MODULE__{
      module: options.module,
      type: options.module.membrane_element_type(),
      name: options.name,
      internal_state: nil,
      parent_pid: options.parent,
      supplying_demand?: false,
      delayed_demands: MapSet.new(),
      synchronization: %{
        parent_clock: options.parent_clock,
        timers: %{},
        clock: nil,
        stream_sync: options.sync,
        latency: 0
      },
      initialized?: false,
      playback: :stopped,
      playback_queue: [],
      resource_guard: options.resource_guard,
      subprocess_supervisor: options.subprocess_supervisor,
      terminating?: false,
      setup_incomplete?: false
    }
    |> PadSpecHandler.init_pads()
  end
end
