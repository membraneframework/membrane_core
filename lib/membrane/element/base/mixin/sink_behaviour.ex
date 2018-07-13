defmodule Membrane.Element.Base.Mixin.SinkBehaviour do
  @moduledoc """
  Module defining behaviour for sink and filter elements.

  When used declares behaviour implementation, provides default callback definitions
  and imports macros.

  For more information on implementing elements, see `Membrane.Element.Base`.
  """

  alias Membrane.{Caps, Element}
  alias Element.{Context, Pad}
  alias Element.Base.Mixin.CommonBehaviour

  @doc """
  Callback that defines what sink pads may be ever available for this
  element type.

  The default name for generic sink pad, in elements that just consume some
  buffers is `:sink`.
  """
  @callback known_sink_pads() :: [Element.sink_pad_specs_t()]

  @doc """
  Callback invoked when Element is receiving information about new caps for
  given pad. In filters those caps are forwarded through all source pads by default.
  """
  @callback handle_caps(
              pad :: Pad.name_t(),
              caps :: Membrane.Caps.t(),
              context :: Context.Caps.t(),
              state :: Element.state_t()
            ) :: CommonBehaviour.callback_return_t()

  @doc """
  Macro that defines known sink pads for the element type.

  Allows to use `Membrane.Caps.Matcher.one_of/1` and `Membrane.Caps.Matcher.range/2`
  functions without module prefix.

  It automatically generates documentation from the given definition
  and adds compile-time caps specs validation.
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
      #{unquote(sink_pads) |> Membrane.Core.Helper.Doc.generate_known_pads_docs()}
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

      @impl true
      def handle_caps(_pad, _caps, _context, state), do: {:ok, state}

      defoverridable handle_caps: 4
    end
  end
end
