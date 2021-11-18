defmodule Membrane.Bin.PadData do
  @moduledoc """
  Struct describing current pad state.

  The public fields are:
    - `:accepted_caps` - specification of possible caps that are accepted on the pad.
      See `Membrane.Caps.Matcher` for more information. This field only applies to elements' pads.
    - `:availability` - see `Membrane.Pad.availability_t`
    - `:caps` - the most recent `Membrane.Caps` that have been sent (output) or received (input)
      on the pad. May be `nil` if not yet set. This field only applies to elements' pads.
    - `:demand` - current demand requested on the pad working in pull mode. This field only applies to elements' pads.
    - `:direction` - see `Membrane.Pad.direction_t`
    - `:end_of_stream?` - flag determining whether the stream processing via the pad has been finished
    - `:mode` - see `Membrane.Pad.mode_t`. This field only applies to elements' pads.
    - `:name` - see `Membrane.Pad.name_t`. Do not mistake with `:ref`
    - `:options` - options passed in `Membrane.ParentSpec` when linking pad
    - `:ref` - see `Membrane.Pad.ref_t`
    - `:start_of_stream?` - flag determining whether the stream processing via the pad has been started

  Other fields in the struct ARE NOT PART OF THE PUBLIC API and should not be
  accessed or relied on.
  """
  use Bunch.Access

  @type t :: %__MODULE__{
          ref: Membrane.Pad.ref_t(),
          link_id: Membrane.Core.Parent.ChildLifeController.LinkHandler.link_id_t(),
          endpoint: Membrane.Core.Parent.Link.Endpoint.t(),
          linked?: boolean(),
          response_received?: boolean(),
          spec_ref: Membrane.Core.Parent.ChildLifeController.spec_ref_t(),
          options: Membrane.ParentSpec.pad_props_t()
        }

  defstruct [:ref, :link_id, :endpoint, :linked?, :response_received?, :spec_ref, :options]
end
