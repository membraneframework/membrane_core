defmodule Membrane.Element.Base.Mixin.SinkBehaviour do
  @moduledoc false


  @doc """
  Callback that defines what sink pads may be ever available for this
  element type.

  It should return a map where:

  * key contains pad name. That may be either atom (like `:sink`,
    `:something_else` for pads that are always available, or string for pads
    that are added dynamically),
  * value is a tuple where:
    * first item of the tuple contains pad availability. It may be set only
      `:always` at the moment,
    * second item of the tuple contains pad mode (`:pull` or `:push`),
    * third item of the tuple contains `:any` or list of caps that can be
      knownly generated from this pad.

  The default name for generic sink pad, in elements that just consume some
  buffers is `:sink`.
  """
  @callback known_sink_pads() :: Membrane.Pad.known_pads_t


  @doc """
  Macro that defines known sink pads for the element type.

  It automatically generates documentation from the given definition.
  """
  defmacro def_known_sink_pads(sink_pads) do
    quote do
      @spec known_sink_pads() :: Membrane.Pad.known_pads_t
      @impl true
      def known_sink_pads(), do: unquote(sink_pads)
    end
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      import unquote(__MODULE__), only: [def_known_sink_pads: 1]
    end
  end
end
