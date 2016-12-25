defmodule Membrane.Element.Base.Mixin.SinkBehaviour do
  @moduledoc false


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
      module_name = String.slice(to_string(__MODULE__),
        String.length("Elixir."), String.length(to_string(__MODULE__)))

      docstring =
        "Returns all known sink pads for `#{module_name}`.\n\n" <>
        "They are the following:\n\n" <>
        Membrane.Helper.Doc.generate_known_pads_docs(unquote(sink_pads))

      Module.add_doc(__MODULE__, __ENV__.line + 1, :def, {:known_sink_pads, 0}, [], docstring)
      @spec known_sink_pads() :: Membrane.Pad.known_pads_t
      def known_sink_pads(), do: unquote(sink_pads)
    end
  end


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Element.Base.Mixin.SinkBehaviour

      import Membrane.Element.Base.Mixin.SinkBehaviour, only: [def_known_sink_pads: 1]
    end
  end
end
