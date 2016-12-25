defmodule Membrane.Element.Base.Mixin.SinkBehaviour do
  @doc """
  Callback that is called when buffer arrives.

  The arguments are:

  * buffer
  * current element state

  While implementing these callbacks, please use pattern matching to define
  what caps are supported. In other words, define one function matching this
  signature per each caps supported.
  """
  @callback handle_buffer(%Membrane.Buffer{}, any) ::
    {:ok, any} |
    {:send, [%Membrane.Buffer{}], any} |
    {:error, any, any}


  @doc """
  Callback that defines what sink pads may be ever available for this
  element type.

  It should return a map where:

  * key contains pad name. That may be either atom (like `:src`, `:sink`,
    `:something_else` for pads that are always available, or String for pads
    that are added dynamically),
  * value is a tuple where first element of a tuple contains pad availability.
    That may be only `:always` at the moment,
  * second element of a tuple contains `:any` or list of caps that can be
    potentially generated from this pad.

  The default name for generic sink pad, in elements that just consume some
  buffers is `:sink`.
  """
  @callback potential_sink_pads() :: Membrane.Pad.potential_pads_t


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Element.Base.Mixin.SinkBehaviour
    end
  end
end
