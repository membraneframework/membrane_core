defmodule Membrane.Element.PadData do
  @moduledoc """
  Struct describing current pad state.

  The public fields are:
    - `:accepted_caps` - specification of possible caps that are accepted on the pad.
      See `Membrane.Caps.Matcher` for more information.
    - `:availability` - see `t:Membrane.Pad.availability_t/0`
    - `:caps` - the most recent `Membrane.Caps` that have been sent (output) or received (input)
      on the pad. May be `nil` if not yet set.
    - `:demand` - current demand requested on the pad working in pull mode.
    - `:direction` - see `t:Membrane.Pad.direction_t/0`
    - `:end_of_stream?` - flag determining whether the stream processing via the pad has been finished
    - `:mode` - see `t:Membrane.Pad.mode_t/0`.
    - `:name` - see `t:Membrane.Pad.name_t/0`. Do not mistake with `:ref`
    - `:options` - options passed in `Membrane.ParentSpec` when linking pad
    - `:ref` - see `t:Membrane.Pad.ref_t/0`
    - `:start_of_stream?` - flag determining whether the stream processing via the pad has been started

  Other fields in the struct ARE NOT PART OF THE PUBLIC API and should not be
  accessed or relied on.
  """
  use Bunch.Access

  alias Membrane.{Caps, Pad}

  @type private_field :: term()

  @type t :: %__MODULE__{
          accepted_caps: Caps.Matcher.caps_specs_t(),
          availability: Pad.availability_t(),
          caps: Caps.t() | nil,
          start_of_stream?: boolean(),
          end_of_stream?: boolean(),
          direction: Pad.direction_t(),
          mode: Pad.mode_t(),
          name: Pad.name_t(),
          ref: Pad.ref_t(),
          options: %{optional(atom) => any},
          pid: private_field,
          other_ref: private_field,
          input_queue: private_field,
          demand: integer() | nil,
          demand_mode: private_field,
          demand_unit: private_field,
          other_demand_unit: private_field,
          auto_demand_size: private_field(),
          sticky_messages: private_field,
          toilet: private_field,
          associated_pads: private_field
        }

  @enforce_keys [
    :accepted_caps,
    :availability,
    :caps,
    :direction,
    :mode,
    :name,
    :ref,
    :options,
    :pid,
    :other_ref
  ]

  defstruct @enforce_keys ++
              [
                input_queue: nil,
                demand: nil,
                demand_mode: nil,
                demand_unit: nil,
                start_of_stream?: false,
                end_of_stream?: false,
                other_demand_unit: nil,
                auto_demand_size: nil,
                sticky_messages: [],
                toilet: nil,
                associated_pads: []
              ]
end
