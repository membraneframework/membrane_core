defmodule Membrane.Element.Pad.Data do
  @moduledoc """
  Struct describing current pad state.

  The public fields are:
    - `caps` - `Membrane.Caps` on the pad (may be `nil` if not yet set)
    - `start_of_stream?` - flag determining whether `Membrane.Event.StartOfStream`
      has been received on the pad
    - `end_of_stream?` - flag determining whether `Membrane.Event.EndOfStream`
      has been received on the pad

  Other fields in the struct ARE NOT PART OF THE PUBLIC API and should not be
  accessed or relied on.
  """
  alias Membrane.Element.Pad
  alias Membrane.{Buffer, Caps, Core, Event}
  alias Buffer.Metric
  alias Core.PullBuffer
  use Bunch.Access

  @type t :: %__MODULE__{
          accepted_caps: any,
          availability: Pad.availability_t(),
          direction: Pad.direction_t(),
          mode: Pad.mode_t(),
          demand_unit: Metric.unit_t(),
          other_demand_unit: Metric.unit_t(),
          current_id: non_neg_integer,
          pid: pid,
          other_ref: Pad.ref_t(),
          caps: Caps.t() | nil,
          start_of_stream?: boolean(),
          end_of_stream?: boolean(),
          sticky_messages: [Event.t()],
          buffer: PullBuffer.t(),
          demand: integer(),
          opts: any()
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
    :buffer,
    :demand,
    :opts
  ]
end
