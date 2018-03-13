defmodule Membrane.Element.Base.Mixin.SourceBehaviour do
  @moduledoc false

  alias Membrane.Caps

  @doc """
  Callback that defines what source pads may be ever available for this
  element type.

  It should return a map where:

  * key contains pad name. That may be either atom (like `:source`,
    `:something_else` for pads that are always available, or string for pads
    that are added dynamically),
  * value is a tuple where:
    * first item of the tuple contains pad availability. It may be set only
      `:always` at the moment,
    * second item of the tuple contains pad mode (`:pull` or `:push`),
    * third item of the tuple contains `:any` or list of caps that can be
      knownly generated from this pad.

  The default name for generic source pad, in elements that just produce some
  buffers is `:source`.
  """
  @callback known_source_pads() :: Membrane.Pad.known_pads_t()

  # FIXME: Bring back documentation generation or don't mention it in the macro doc
  @doc """
  Macro that defines known source pads for the element type.

  It automatically generates documentation from the given definition
  and adds compile-time caps specs validation
  """
  defmacro def_known_source_pads(source_pads) do
    quote do
      @spec known_source_pads() :: Membrane.Pad.known_pads_t()
      def known_source_pads(), do: unquote(source_pads)

      @after_compile {__MODULE__, :__membrane_source_caps_specs_validation__}

      def __membrane_source_caps_specs_validation__(env, _bytecode) do
        pads_list = env.module.known_source_pads() |> Map.values()

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

  @doc """
  Callback that is called when buffer should be emitted by the source or filter.

  It will be called only for pads in the pull mode, as in their case demand
  is triggered by the sinks.

  For pads in the push mode, Elemen should generate buffers without this
  callback. Example scenario might be reading a stream over TCP, waiting
  for incoming packets that will be delivered to the PID of the element,
  which will result in calling `handle_other/2`, which can return value that
  contains the `:buffer` action.

  It is safe to use blocking reads in the filter. It will cause limiting
  throughput of the pipeline to the capability of the source.

  The arguments are:

  * name of the pad receiving a demand request,
  * requested number of units
  * unit
  * context (`Membrane.Element.Context.Demand`)
  * current element's state.
  """
  @callback handle_demand(
              Membrane.Element.Pad.name_t(),
              non_neg_integer,
              Membrane.Buffer.Metric.unit_t(),
              Membrane.Context.Demand.t(),
              Membrane.Element.Manager.State.internal_state_t()
            ) :: Membrane.Element.Base.Mixin.CommonBehaviour.callback_return_t()

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Element.Base.Mixin.SourceBehaviour

      import Membrane.Element.Base.Mixin.SourceBehaviour, only: [def_known_source_pads: 1]
    end
  end
end
