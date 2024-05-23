defmodule Membrane.Bin.PadData do
  @moduledoc """
  Struct describing current pad state.

  The public fields are:
    - `:availability` - see `t:Membrane.Pad.availability/0`
    - `:direction` - see `t:Membrane.Pad.direction/0`
    - `:name` - see `t:Membrane.Pad.name/0`. Do not mistake with `:ref`
    - `:options` - options passed in `Membrane.ChildrenSpec` when linking pad
    - `:ref` - see `t:Membrane.Pad.ref/0`

  Other fields in the struct ARE NOT PART OF THE PUBLIC API and should not be
  accessed or relied on.
  """
  use Bunch.Access

  @type private_field :: term()

  @typedoc @moduledoc
  @type t :: %__MODULE__{
          ref: Membrane.Pad.ref(),
          options: Membrane.ChildrenSpec.pad_options(),
          availability: Membrane.Pad.availability(),
          direction: Membrane.Pad.direction(),
          name: Membrane.Pad.name(),
          spec_ref: private_field,
          link_id: private_field,
          endpoint: private_field,
          linked?: private_field,
          response_received?: private_field,
          linking_timeout_ref: private_field
        }

  @enforce_keys [
    :ref,
    :options,
    :availability,
    :direction,
    :name,
    :link_id,
    :endpoint,
    :linked?,
    :response_received?,
    :spec_ref
  ]

  defstruct @enforce_keys ++ [:linking_timeout_ref]
end
