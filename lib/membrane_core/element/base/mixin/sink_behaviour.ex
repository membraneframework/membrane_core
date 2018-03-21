defmodule Membrane.Element.Base.Mixin.SinkBehaviour do
  @moduledoc false

  alias Membrane.Caps

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
  @callback known_sink_pads() :: Membrane.Pad.known_pads_t()

  @doc """
  Macro that defines known sink pads for the element type.

  Allows to use `one_of/1` and `range/2` functions from `Membrane.Caps.Matcher`
  without module prefix

  It automatically generates documentation from the given definition
  and adds compile-time caps specs validation
  """
  defmacro def_known_sink_pads(raw_sink_pads) do
    sink_pads =
      raw_sink_pads
      |> Membrane.Helper.Macro.inject_calls([
        {Caps.Matcher, :one_of},
        {Caps.Matcher, :range}
      ])

    quote do
      @doc """
      Returns all known sink pads for #{inspect(__MODULE__)}

      They are the following:
      #{unquote(sink_pads) |> Membrane.Helper.Doc.generate_known_pads_docs()}
      """
      @spec known_sink_pads() :: Membrane.Pad.known_pads_t()
      def known_sink_pads(), do: unquote(sink_pads)

      @after_compile {__MODULE__, :__membrane_sink_caps_specs_validation__}

      def __membrane_sink_caps_specs_validation__(env, _bytecode) do
        pads_list = env.module.known_sink_pads() |> Map.values()

        for {_, _, caps_spec} <- pads_list do
          with :ok <- caps_spec |> Caps.Matcher.validate_specs() do
            :ok
          else
            {:error, reason} -> raise "Error in sink caps spec: #{inspect(reason)}"
          end
        end
      end
    end
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Element.Base.Mixin.SinkBehaviour

      import Membrane.Element.Base.Mixin.SinkBehaviour, only: [def_known_sink_pads: 1]
    end
  end
end
