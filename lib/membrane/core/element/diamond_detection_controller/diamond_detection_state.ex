defmodule Membrane.Core.Element.DiamondDetectionController.DiamondDatectionState do
  @moduledoc false

  use Bunch.Access

  alias Membrane.Core.Element.DiamondDetectionController.PathInGraph

  defstruct [
    :serialized_component_path,
    ref_to_path: %{},
    trigger_refs: MapSet.new(),
    postponed?: false
  ]

  @type t :: %__MODULE__{
          serialized_component_path: String.t() | nil,
          ref_to_path: %{optional(reference()) => PathInGraph.t()},
          trigger_refs: MapSet.t(reference()),
          postponed?: boolean()
        }
end
