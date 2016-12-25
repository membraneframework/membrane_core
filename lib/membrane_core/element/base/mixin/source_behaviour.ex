defmodule Membrane.Element.Base.Mixin.SourceBehaviour do
  @moduledoc false


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
    knownly generated from this pad.

  The default name for generic source pad, in elements that just produce some
  buffers is `:source`.
  """
  @callback known_source_pads() :: Membrane.Pad.known_pads_t


  @doc """
  Macro that defines known source pads for the element type.

  It automatically generates documentation from the given definition.
  """
  defmacro def_known_source_pads(source_pads) do
    quote do
      module_name = String.slice(to_string(__MODULE__),
        String.length("Elixir."), String.length(to_string(__MODULE__)))

      docstring =
        "Returns all known source pads for `#{module_name}`.\n\n" <>
        "They are the following:\n\n" <>
        Membrane.Helper.Doc.generate_known_pads_docs(unquote(source_pads))

      Module.add_doc(__MODULE__, __ENV__.line + 1, :def, {:known_source_pads, 0}, [], docstring)
      @spec known_source_pads() :: Membrane.Pad.known_pads_t
      def known_source_pads(), do: unquote(source_pads)
    end
  end


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Element.Base.Mixin.SourceBehaviour

      import Membrane.Element.Base.Mixin.SourceBehaviour, only: [def_known_source_pads: 1]
    end
  end
end
