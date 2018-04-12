defmodule Membrane.Element.Base.Mixin.SinkBehaviour do
  @moduledoc """
  Module defining behaviour for sink elements.

  When used, declares behaviour implementation and imports macros.
  """

  alias Membrane.{Buffer, Caps, Element.Pad}

  @type known_sink_pads_t :: [
          {Pad.name_t(),
           {:always, {:push | :pull, demand_in: Buffer.Metric.unit_t()},
            Caps.Matcher.caps_specs_t()}}
        ]

  @doc """
  Callback that defines what sink pads may be ever available for this
  element type.

  The default name for generic sink pad, in elements that just consume some
  buffers is `:sink`.
  """
  @callback known_sink_pads() :: known_sink_pads_t()

  @doc """
  Macro that defines known sink pads for the element type.

  Allows to use `Membrane.Caps.Matcher.one_of/1` and `Membrane.Caps.Matcher.range/2`
  functions without module prefix

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
      @spec known_sink_pads() :: unquote(__MODULE__).known_sink_pads_t
      @impl true
      def known_sink_pads(), do: unquote(sink_pads)

      @after_compile {__MODULE__, :__membrane_sink_caps_specs_validation__}

      def __membrane_sink_caps_specs_validation__(env, _bytecode) do
        pads_list = env.module.known_sink_pads() |> Enum.to_list() |> Keyword.values()

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
      @behaviour unquote(__MODULE__)

      import unquote(__MODULE__), only: [def_known_sink_pads: 1]
    end
  end
end
