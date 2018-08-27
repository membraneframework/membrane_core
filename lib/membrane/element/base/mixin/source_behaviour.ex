defmodule Membrane.Element.Base.Mixin.SourceBehaviour do
  @moduledoc """
  Module defining behaviour for source and filter elements.

  When used declares behaviour implementation, provides default callback definitions
  and imports macros.

  For more information on implementing elements, see `Membrane.Element.Base`.
  """

  alias Membrane.{Buffer, Caps, Element}
  alias Element.{CallbackContext, Pad}
  alias Element.Base.Mixin.CommonBehaviour

  @doc """
  Callback that defines what source pads may be ever available for this
  element type.

  The default name for generic source pad, in elements that just produce some
  buffers is `:source`.
  """
  @callback known_source_pads() :: [Element.source_pad_specs_t()]

  @doc """
  Callback that is called when buffers should be emitted by the source or filter.

  It will be called only for source pads in the pull mode, as in their case demand
  is triggered by the sinks of the subsequent elements.

  In source elements, appropriate amount of data should be sent here. If it happens
  not to be yet available, element should store unsupplied demand and supply it
  when possible.

  In filter elements, this callback should usually return `:demand` action with
  size sufficient (at least approximately) for supplying incoming demand. This
  will result with calling `c:Membrane.Element.Base.Filter.handle_process/4` or
  `c:Membrane.Element.Base.Sink.handle_write/4`, which is to supply
  the demand. If it does not, or does only partially,
  `c:Membrane.Element.Base.Mixin.SourceBehaviour.handle_demand/5` is called
  again, until there is any data available on the sink pad.

  For sources in the push mode, element should generate buffers without this
  callback.
  """
  @callback handle_demand(
              pad :: Pad.name_t(),
              size :: non_neg_integer,
              unit :: Buffer.Metric.unit_t(),
              context :: CallbackContext.Demand.t(),
              state :: Element.state_t()
            ) :: CommonBehaviour.callback_return_t()

  @doc """
  Macro that defines known source pads for the element type.

  Allows to use `one_of/1` and `range/2` functions from `Membrane.Caps.Matcher`
  without module prefix.

  It automatically generates documentation from the given definition
  and adds compile-time caps specs validation.
  """
  defmacro def_known_source_pads(raw_source_pads) do
    source_pads =
      raw_source_pads
      |> Membrane.Helper.Macro.inject_calls([
        {Caps.Matcher, :one_of},
        {Caps.Matcher, :range}
      ])

    quote do
      @doc """
      Returns all known source pads for #{inspect(__MODULE__)}

      They are the following:
      #{unquote(source_pads) |> Membrane.Core.Helper.Doc.generate_known_pads_docs()}
      """
      @spec known_source_pads() :: [Membrane.Element.source_pad_specs_t()]
      @impl true
      def known_source_pads(), do: unquote(source_pads)

      @after_compile {__MODULE__, :__membrane_source_caps_specs_validation__}

      def __membrane_source_caps_specs_validation__(env, _bytecode) do
        pads_list = env.module.known_source_pads() |> Enum.to_list() |> Keyword.values()

        for {_, _, caps_spec} <- pads_list do
          with :ok <- caps_spec |> Caps.Matcher.validate_specs() do
            :ok
          else
            {:error, reason} -> raise "Error in source caps spec: #{inspect(reason)}"
          end
        end
      end
    end
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      import unquote(__MODULE__), only: [def_known_source_pads: 1]
    end
  end
end
