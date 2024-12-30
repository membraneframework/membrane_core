defmodule Membrane.Core.Element.DiamondDetectionController.PathInGraph do
  @moduledoc false

  defmodule Vertex do
    @moduledoc false
    require Membrane.Pad, as: Pad

    defstruct [:pid, :component_path, :input_pad_ref, :output_pad_ref]

    @type t :: %__MODULE__{
            pid: pid(),
            component_path: String.t(),
            input_pad_ref: Pad.ref() | nil,
            output_pad_ref: Pad.ref() | nil
          }
  end

  @type t :: [Vertex.t()]
end
