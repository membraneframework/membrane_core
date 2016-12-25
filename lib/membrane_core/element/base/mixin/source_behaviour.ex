defmodule Membrane.Element.Base.Mixin.SourceBehaviour do
  @doc """
  Callback that defines what source pads may be ever available for this
  element type.

  It should return a map where:

  * key contains pad name. That may be either atom (like `:src`, `:sink`,
    `:something_else` for pads that are always available, or String for pads
    that are added dynamically),
  * value is a tuple where first element of a tuple contains pad availability.
    That may be only `:always` at the moment,
  * second element of a tuple contains `:any` or list of caps that can be
    potentially generated from this pad.

  The default name for generic source pad, in elements that just produce some
  buffers is `:source`.
  """
  @callback potential_source_pads() :: Membrane.Pad.potential_pads_t


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Element.Base.Mixin.SourceBehaviour
    end
  end
end
