defmodule Membrane.Core.Element.DiamondDetectionController.DiamondDatectionState do
  @moduledoc false

  use Bunch.Access

  alias Membrane.Core.Element.DiamondDetectionController.PathInGraph

  defstruct ref_to_path: %{},
            trigger_refs: MapSet.new(),
            postponed?: false

  @type t :: %__MODULE__{
          ref_to_path: %{optional(reference()) => PathInGraph.t()},
          trigger_refs: MapSet.t(reference()),
          postponed?: boolean()
        }
end
