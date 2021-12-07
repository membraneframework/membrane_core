defmodule Membrane.Bin.PadData do
  @moduledoc """
  Struct describing current pad state.

  The public fields are:
    - `:accepted_caps` - specification of possible caps that are accepted on the pad.
      See `Membrane.Caps.Matcher` for more information.
    - `:availability` - see `Membrane.Pad.availability_t`
    - `:direction` - see `Membrane.Pad.direction_t`
    - `:mode` - see `Membrane.Pad.mode_t`
    - `:name` - see `Membrane.Pad.name_t`. Do not mistake with `:ref`
    - `:options` - options passed in `Membrane.ParentSpec` when linking pad
    - `:ref` - see `Membrane.Pad.ref_t`

  Other fields in the struct ARE NOT PART OF THE PUBLIC API and should not be
  accessed or relied on.
  """
  use Bunch.Access

  @type private_field :: term()

  @type t :: %__MODULE__{
          ref: Membrane.Pad.ref_t(),
          options: Membrane.ParentSpec.pad_props_t(),
          accepted_caps: Membrane.Caps.Matcher.caps_specs_t(),
          availability: Membrane.Pad.availability_t(),
          direction: Membrane.Pad.direction_t(),
          mode: Membrane.Pad.mode_t(),
          name: Membrane.Pad.name_t(),
          link_id: private_field,
          endpoint: private_field,
          linked?: private_field,
          response_received?: private_field,
          spec_ref: private_field,
          demand_unit: private_field
        }

  @enforce_keysx [
    :ref,
    :link_id,
    :endpoint,
    :linked?,
    :response_received?,
    :spec_ref,
    :options,
    :accepted_caps,
    :availability,
    :direction,
    :mode,
    :name
  ]

  defstruct @enforce_keysx ++ [demand_unit: nil]
end
