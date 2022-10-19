defmodule Membrane.Core.Parent.Link.Endpoint do
  @moduledoc false

  use Bunch.Access

  alias Membrane.{Element, Pad}

  @enforce_keys [:child, :pad_spec]
  defstruct @enforce_keys ++
              [pad_ref: nil, pid: nil, pad_props: [], pad_info: %{}, child_spec_ref: nil]

  @type t() :: %__MODULE__{
          child: Element.name_t() | {Membrane.Bin, :itself},
          pad_spec: Pad.name_t() | Pad.ref_t(),
          pad_ref: Pad.ref_t(),
          pid: pid(),
          pad_props: map(),
          pad_info: map()
        }
end
