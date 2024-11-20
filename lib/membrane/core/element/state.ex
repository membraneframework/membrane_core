defmodule Membrane.Core.Element.State do
  @moduledoc false

  # Structure representing state of an Core.Element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Bunch.Access

  alias Membrane.{Clock, Element, Pad, Sync}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.{DiamondDetectionController, EffectiveFlowController}
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
          delay_demands?: boolean(),
          delayed_demands: MapSet.t({Pad.ref(), :supply | :redemand}),
          handle_demand_loop_counter: non_neg_integer(),
          synchronization: %{
            timers: %{Timer.id() => Timer.t()},
            parent_clock: Clock.t(),
            latency: Membrane.Time.non_neg(),
            stream_sync: Sync.t(),
            clock: Clock.t() | nil
          },
          auto_input_pads: [Pad.ref()],
          initialized?: boolean(),
          playback: Membrane.Playback.t(),
          playback_queue: Membrane.Core.Element.PlaybackQueue.t(),
          resource_guard: Membrane.ResourceGuard.t(),
          subprocess_supervisor: pid,
          terminating?: boolean(),
          setup_incomplete?: boolean(),
          effective_flow_control: EffectiveFlowController.effective_flow_control(),
          popping_auto_flow_queue?: boolean(),
          pads_to_snapshot: MapSet.t(),
          stalker: Membrane.Core.Stalker.t(),
          satisfied_auto_output_pads: MapSet.t(),
          awaiting_auto_input_pads: MapSet.t(),
          resume_delayed_demands_loop_in_mailbox?: boolean(),
          diamond_detection_ref_to_path: %{
            optional(reference()) => DiamondDetectionController.diamond_detection_path()
          }
        }

  # READ THIS BEFORE ADDING NEW FIELD!!!

  # Fields of this structure will be inspected in the same order, in which they occur in the
  # list passed to `defstruct`. Take a look at lib/membrane/core/inspect.ex to get more info.
  # If you want to add a new field to the state, place it at the spot corresponding to its
  # importance and possibly near other related fields. It is suggested, to keep `:pads_data`
  # as the last item in the list, because sometimes it is so big, that everything after it
  # might be truncated during the inspection.

  defstruct module: nil,
            name: nil,
            parent_pid: nil,
            playback: :stopped,
            type: nil,
            internal_state: nil,
            pads_info: %{},
            synchronization: nil,
            delayed_demands: MapSet.new(),
            effective_flow_control: :push,
            initialized?: false,
            terminating?: false,
            setup_incomplete?: false,
            delay_demands?: false,
            popping_auto_flow_queue?: false,
            stalker: nil,
            resource_guard: nil,
            subprocess_supervisor: nil,
            handle_demand_loop_counter: 0,
            pads_to_snapshot: MapSet.new(),
            playback_queue: [],
            diamond_detection_ref_to_path: %{},
            pads_data: %{},
            satisfied_auto_output_pads: MapSet.new(),
            awaiting_auto_input_pads: MapSet.new(),
            auto_input_pads: [],
            resume_delayed_demands_loop_in_mailbox?: false
end
