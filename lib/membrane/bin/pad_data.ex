defmodule Membrane.Bin.PadData do
  @moduledoc """
  Struct describing current pad state.

  The public fields are:
    - `:availability` - see `t:Membrane.Pad.availability_t/0`
    - `:direction` - see `t:Membrane.Pad.direction_t/0`
    - `:mode` - see `t:Membrane.Pad.mode_t/0`
    - `:name` - see `t:Membrane.Pad.name_t/0`. Do not mistake with `:ref`
    - `:options` - options passed in `Membrane.ChildrenSpec` when linking pad
    - `:ref` - see `t:Membrane.Pad.ref_t/0`

  Other fields in the struct ARE NOT PART OF THE PUBLIC API and should not be
  accessed or relied on.
  """
  use Bunch.Access

  @type private_field :: term()

  @type t :: %__MODULE__{
          ref: Membrane.Pad.ref_t(),
          options: Membrane.ChildrenSpec.pad_options_t(),
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

  @enforce_keys [
    :ref,
    :options,
    :availability,
    :direction,
    :mode,
    :name,
    :link_id,
    :endpoint,
    :linked?,
    :response_received?,
    :spec_ref
  ]

  defstruct @enforce_keys ++ [demand_unit: nil]
end
