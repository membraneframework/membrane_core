defmodule Membrane.Core.Element.State do
  @moduledoc false

  # Structure representing state of an Core.Element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Bunch.Access

  alias Membrane.{Clock, Element, Pad, Sync}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.DiamondDetectionController.DiamondDatectionState
  alias Membrane.Core.Element.EffectiveFlowController
  alias Membrane.Core.Timer

  @type t :: %__MODULE__{
          module: module(),
          name: Element.name(),
          parent_pid: pid(),
          playback: Membrane.Playback.t(),
          type: Element.type(),
          internal_state: Element.state() | nil,
          pads_info: PadModel.pads_info() | nil,
          synchronization: %{
            timers: %{Timer.id() => Timer.t()},
            parent_clock: Clock.t(),
            latency: Membrane.Time.non_neg(),
            stream_sync: Sync.t(),
            clock: Clock.t() | nil
          },
          delayed_demands: MapSet.t({Pad.ref(), :supply | :redemand}),
          effective_flow_control: EffectiveFlowController.effective_flow_control(),
          initialized?: boolean(),
          terminating?: boolean(),
          setup_incomplete_returned?: boolean(),
          delay_demands?: boolean(),
          popping_auto_flow_queue?: boolean(),
          stalker: Membrane.Core.Stalker.t(),
          resource_guard: Membrane.ResourceGuard.t(),
          subprocess_supervisor: pid(),
          handle_demand_loop_counter: non_neg_integer(),
          pads_to_snapshot: MapSet.t(),
          playback_queue: Membrane.Core.Element.PlaybackQueue.t(),
          diamond_detection_state: DiamondDatectionState.t(),
          pads_data: PadModel.pads_data() | nil,
          satisfied_auto_output_pads: MapSet.t(),
          awaiting_auto_input_pads: MapSet.t(),
          auto_input_pads: [Pad.ref()],
          resume_delayed_demands_loop_in_mailbox?: boolean()
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
            setup_incomplete_returned?: false,
            delay_demands?: false,
            popping_auto_flow_queue?: false,
            stalker: nil,
            resource_guard: nil,
            subprocess_supervisor: nil,
            handle_demand_loop_counter: 0,
            pads_to_snapshot: MapSet.new(),
            playback_queue: [],
            diamond_detection_state: %DiamondDatectionState{},
            pads_data: %{},
            satisfied_auto_output_pads: MapSet.new(),
            awaiting_auto_input_pads: MapSet.new(),
            auto_input_pads: [],
            resume_delayed_demands_loop_in_mailbox?: false
end

defmodule Membrane.Core.Element.State1 do
  @moduledoc false

  # Structure representing state of an Core.Element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Bunch.Access

  alias Membrane.{Clock, Element, Pad, Sync}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.DiamondDetectionController.DiamondDatectionState
  alias Membrane.Core.Element.EffectiveFlowController
  alias Membrane.Core.Timer

  @type t :: %__MODULE__{
          # module: module(),
          # name: Element.name(),
          # parent_pid: pid() | nil,
          # playback: Membrane.Playback.t(),
          # type: Element.type(),
          # internal_state: Element.state() | nil,
          # pads_info: PadModel.pads_info() | nil,
          # synchronization: %{
          # timers: %{Timer.id() => Timer.t()},
          # parent_clock: Clock.t(),
          # latency: Membrane.Time.non_neg(),
          # stream_sync: Sync.t(),
          # clock: Clock.t() | nil
          # },
          delayed_demands: MapSet.t()
          # effective_flow_control: EffectiveFlowController.effective_flow_control(),
          # initialized?: boolean(),
          # terminating?: boolean()
          # setup_incomplete_returned?: boolean(),
          # delay_demands?: boolean(),
          # popping_auto_flow_queue?: boolean(),
          # stalker: Membrane.Core.Stalker.t(),
          # resource_guard: Membrane.ResourceGuard.t(),
          # subprocess_supervisor: pid()
          # handle_demand_loop_counter: non_neg_integer(),
          # pads_to_snapshot: MapSet.t(),
          # playback_queue: Membrane.Core.Element.PlaybackQueue.t(),
          # diamond_detection_state: DiamondDatectionState.t(),
          # pads_data: PadModel.pads_data() | nil,
          # satisfied_auto_output_pads: MapSet.t(),
          # awaiting_auto_input_pads: MapSet.t(),
          # auto_input_pads: [Pad.ref()],
          # resume_delayed_demands_loop_in_mailbox?: boolean()
        }

  # READ THIS BEFORE ADDING NEW FIELD!!!

  # Fields of this structure will be inspected in the same order, in which they occur in the
  # list passed to `defstruct`. Take a look at lib/membrane/core/inspect.ex to get more info.
  # If you want to add a new field to the state, place it at the spot corresponding to its
  # importance and possibly near other related fields. It is suggested, to keep `:pads_data`
  # as the last item in the list, because sometimes it is so big, that everything after it
  # might be truncated during the inspection.

  defstruct [
    # name: nil,
    # parent_pid: nil,
    # playback: :stopped,
    # type: nil,

    # internal_state: nil,
    # pads_info: %{},
    # synchronization: nil,
    delayed_demands: MapSet.new()
  ]

  # effective_flow_control: :push,
  # initialized?: false,
  # terminating?: false

  # setup_incomplete_returned?: false,
  # delay_demands?: false,
  # popping_auto_flow_queue?: false,
  # stalker: nil,
  # resource_guard: nil,
  # subprocess_supervisor: nil

  # handle_demand_loop_counter: 0,
  # pads_to_snapshot: MapSet.new(),
  # playback_queue: [],
  # diamond_detection_state: %DiamondDatectionState{},
  # pads_data: %{},
  # satisfied_auto_output_pads: MapSet.new(),
  # awaiting_auto_input_pads: MapSet.new(),
  # auto_input_pads: [],
  # resume_delayed_demands_loop_in_mailbox?: false
end
