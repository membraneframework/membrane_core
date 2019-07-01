defmodule Membrane.Element.Pad.Data do
  @moduledoc """
  Struct describing current pad state.

  The public fields are:
    - `:caps` - the most recent `Membrane.Caps` that have been sent (output) or received (input)
      on the pad. May be `nil` if not yet set.
    - `:start_of_stream?` - flag determining whether `Membrane.Event.StartOfStream`
      has been received (or sent) on the pad
    - `:end_of_stream?` - flag determining whether `Membrane.Event.EndOfStream`
      has been received (or sent) on the pad
    - `:options` - options passed in `Membrane.Pipeline.Spec` when linking pad

  Other fields in the struct ARE NOT PART OF THE PUBLIC API and should not be
  accessed or relied on.
  """
  alias Membrane.Element.Pad
  alias Membrane.{Buffer, Caps, Core, Event}
  alias Buffer.Metric
  alias Core.InputBuffer
  use Bunch.Access

  @type t :: %__MODULE__{
          accepted_caps: any,
          availability: Pad.availability_t(),
          direction: Pad.direction_t(),
          mode: Pad.mode_t(),
          demand_unit: Metric.unit_t() | nil,
          other_demand_unit: Metric.unit_t() | nil,
          current_id: non_neg_integer | nil,
          pid: pid,
          other_ref: Pad.ref_t(),
          caps: Caps.t() | nil,
          start_of_stream?: boolean(),
          end_of_stream?: boolean(),
          sticky_messages: [Event.t()],
          input_buf: InputBuffer.t() | nil,
          demand: integer() | nil,
          options: Keyword.t()
        }

  defstruct [
    :accepted_caps,
    :availability,
    :direction,
    :mode,
    :demand_unit,
    :other_demand_unit,
    :current_id,
    :pid,
    :other_ref,
    :caps,
    :start_of_stream?,
    :end_of_stream?,
    :sticky_messages,
    :input_buf,
    :demand,
    :options
  ]
end
