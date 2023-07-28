defmodule Membrane.Element.PadData do
  @moduledoc """
  Struct describing current pad state.

  The public fields are:
    - `:availability` - see `t:Membrane.Pad.availability/0`
    - `:stream_format` - the most recent `t:Membrane.StreamFormat.t/0` that have been sent (output) or received (input)
      on the pad. May be `nil` if not yet set.
    - `:direction` - see `t:Membrane.Pad.direction/0`
    - `:end_of_stream?` - flag determining whether the stream processing via the pad has been finished
    - `:flow_control` - see `t:Membrane.Pad.flow_control/0`.
    - `:name` - see `t:Membrane.Pad.name/0`. Do not mistake with `:ref`
    - `:options` - options passed in `Membrane.ParentSpec` when linking pad
    - `:ref` - see `t:Membrane.Pad.ref/0`
    - `:start_of_stream?` - flag determining whether the stream processing via the pad has been started
    - `auto_demand_paused?` - flag determining if auto-demanding on the pad is paused or no

  Other fields in the struct ARE NOT PART OF THE PUBLIC API and should not be
  accessed or relied on.
  """
  use Bunch.Access

  alias Membrane.{Pad, StreamFormat}

  @type private_field :: term()

  @typedoc @moduledoc
  @type t :: %__MODULE__{
          availability: Pad.availability(),
          stream_format: StreamFormat.t() | nil,
          start_of_stream?: boolean(),
          end_of_stream?: boolean(),
          direction: Pad.direction(),
          flow_control: Pad.flow_control(),
          name: Pad.name(),
          ref: Pad.ref(),
          options: %{optional(atom) => any},
          auto_demand_paused?: boolean(),
          stream_format_validation_params: private_field,
          pid: private_field,
          other_ref: private_field,
          input_queue: private_field,
          incoming_demand: integer() | nil,
          demand_unit: private_field,
          other_demand_unit: private_field,
          auto_demand_size: private_field,
          sticky_messages: private_field,

          # Used only for output pads with :pull or :auto flow control. Holds the last captured value of AtomicDemand,
          # decreased by the size of buffers sent via specific pad since the last capture, expressed in the appropriate metric.
          # Moment, when demand value drops to 0 or less, triggers another capture of AtomicDemand value.
          demand: integer() | nil,

          # Instance of AtomicDemand shared by both sides of link. Holds amount of data, that has been demanded by the element
          # with input pad, but hasn't been sent yet by the element with output pad. Detects toilet overflow as well.
          atomic_demand: private_field,

          # Field used in DemandController.AutoFlowUtils and InputQueue, to caluclate, how much AtomicDemand should be increased.
          # Contains amount of data (:buffers/:bytes), that has been demanded from the element on the other side of link, but
          # hasn't arrived yet. Unused for output pads.
          manual_demand_size: private_field,
          associated_pads: private_field,
          sticky_events: private_field,
          other_effective_flow_control: private_field,
          stalker_metrics: private_field
        }

  @enforce_keys [
    :availability,
    :stream_format,
    :direction,
    :flow_control,
    :name,
    :ref,
    :options,
    :pid,
    :other_ref
  ]

  defstruct @enforce_keys ++
              [
                input_queue: nil,
                demand: 0,
                incoming_demand: nil,
                demand_unit: nil,
                start_of_stream?: false,
                end_of_stream?: false,
                auto_demand_size: nil,
                sticky_messages: [],
                atomic_demand: nil,
                manual_demand_size: 0,
                associated_pads: [],
                sticky_events: [],
                stream_format_validation_params: [],
                other_demand_unit: nil,
                other_effective_flow_control: :push,
                stalker_metrics: %{},
                auto_demand_paused?: false
              ]
end
