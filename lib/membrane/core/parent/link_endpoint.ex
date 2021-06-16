defmodule Membrane.Core.Parent.Link.Endpoint do
  @moduledoc """
  Module defining parent link endpoint.
  """

  alias Membrane.{Element, Pad, ParentSpec}

  @enforce_keys [:child, :pad_spec]
  defstruct @enforce_keys ++ [pad_ref: nil, pid: nil, pad_props: []]

  @type t() :: %__MODULE__{
          child: Element.name_t() | {Membrane.Bin, :itself},
          pad_spec: Pad.name_t() | Pad.ref_t(),
          pad_ref: Pad.ref_t(),
          pid: pid(),
          pad_props: ParentSpec.pad_props_t()
        }
end
