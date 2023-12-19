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
          pad_refs: [Pad.ref()] | nil,
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
          stalker: Membrane.Core.Stalker.t(),
          satisfied_auto_output_pads: MapSet.t(),
          awaiting_auto_input_pads: MapSet.t()
        }

  # READ THIS BEFORE ADDING NEW FIELD!!!

  # Fields of this structure will be inspected in the same order, in which they occur in the
  # list passed to `defstruct`. Take a look at lib/membrane/core/inspect.ex to get more info.
  # If you want to add a new field to the state, place it at the spot corresponding to its
  # importance and possibly near other related fields. It is suggested, to keep `:pads_data`
  # as the last item in the list, because sometimes it is so big, that everything after it
  # might be truncated during the inspection.

  defstruct [
    :module,
    :name,
    :parent_pid,
    :playback,
    :type,
    :internal_state,
    :pad_refs,
    :pads_info,
    :synchronization,
    :delayed_demands,
    :effective_flow_control,
    :initialized?,
    :terminating?,
    :setup_incomplete?,
    :supplying_demand?,
    :handling_action?,
    :stalker,
    :resource_guard,
    :subprocess_supervisor,
    :handle_demand_loop_counter,
    :demand_size,
    :pads_to_snapshot,
    :playback_queue,
    :pads_data,
    :satisfied_auto_output_pads,
    :awaiting_auto_input_pads
  ]
end
