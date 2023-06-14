defmodule Membrane.Core.Element.State do
  @moduledoc false

  # Structure representing state of an Core.Element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Bunch.Access

  alias Membrane.{Clock, Element, Pad, Sync}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.EffectiveFlowController
  alias Membrane.Core.Timer

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
          handle_demand_loop_counter: non_neg_integer(),
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
          effective_flow_control: EffectiveFlowController.effective_flow_control(),
          handling_action?: boolean(),
          pads_to_snapshot: MapSet.t(),
          observer: Membrane.Core.Observer.t()
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
    :handle_demand_loop_counter,
    :synchronization,
    :demand_size,
    :initialized?,
    :playback,
    :playback_queue,
    :resource_guard,
    :subprocess_supervisor,
    :terminating?,
    :setup_incomplete?,
    :effective_flow_control,
    :handling_action?,
    :pads_to_snapshot,
    :observer
  ]
end
