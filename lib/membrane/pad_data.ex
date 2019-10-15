defmodule Membrane.Pad.Data do
  @moduledoc """
  Struct describing current pad state.

  The public fields are:
    - `:caps` - the most recent `Membrane.Caps` that have been sent (output) or received (input)
      on the pad. May be `nil` if not yet set.
    - `:start_of_stream?` - flag determining whether `Membrane.Event.StartOfStream`
      has been received (or sent) on the pad
    - `:end_of_stream?` - flag determining whether `Membrane.Event.EndOfStream`
      has been received (or sent) on the pad
    - `:options` - options passed in `Membrane.ParentSpec` when linking pad

  Other fields in the struct ARE NOT PART OF THE PUBLIC API and should not be
  accessed or relied on.
  """
  alias Membrane.Pad
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
          options: Keyword.t(),
          bin?: boolean()
        }

  defstruct accepted_caps: nil,
            availability: nil,
            direction: nil,
            mode: nil,
            demand_unit: nil,
            other_demand_unit: nil,
            current_id: nil,
            pid: nil,
            other_ref: nil,
            caps: nil,
            start_of_stream?: nil,
            end_of_stream?: nil,
            sticky_messages: nil,
            input_buf: nil,
            demand: nil,
            options: [],
            bin?: false
end
