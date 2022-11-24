defmodule Membrane.Core.FilterAggregator.Context do
  @moduledoc false

  alias Membrane.Element

  require Membrane.Core.FilterAggregator.InternalAction, as: InternalAction

  @type t :: Membrane.Core.Element.CallbackContext.default_fields()

  @typedoc """
  Collection of states for encapsuled elements as kept in `Membrane.FilterAggregator` element
  """
  @type states :: [{Element.name_t(), module(), t(), Element.state_t()}]

  @type action :: Element.Action.t() | Membrane.Core.FilterAggregator.InternalAction.t()

  @spec build_context!(Element.name_t(), module(), t()) :: t()
  def build_context!(name, module, agg_ctx) do
    pad_descriptions = module.membrane_pads()
    pads = pad_descriptions |> MapSet.new(fn {k, _v} -> k end)

    expected_pads = [:input, :output] |> MapSet.new()

    unless MapSet.equal?(pads, expected_pads) do
      raise """
      Element #{inspect(module)} has unsupported pads.
      For more info on supported pads see the docs of `Membrane.FilterAggregator`
      #{inspect(module)}'s pads: : #{inspect(MapSet.to_list(pads))}
      """
    end

    ensure_auto_demands!(pad_descriptions[:input], module)
    ensure_auto_demands!(pad_descriptions[:output], module)

    pads_data =
      pad_descriptions
      |> Map.new(fn {name, description} -> {name, build_pad_data(description)} end)

    %{
      pads: pads_data,
      clock: nil,
      name: name,
      parent_clock: nil,
      playback: :stopped,
      resource_guard: agg_ctx.resource_guard,
      utility_supervisor: agg_ctx.utility_supervisor
    }
  end

  defp ensure_auto_demands!(%{name: name, mode: :pull, demand_mode: mode}, module)
       when mode != :auto do
    raise """
    `Membrane.FilterAggregator` supports only filters with demands in `:auto` mode.
    Pad `#{inspect(name)}` of `#{inspect(module)}` uses `#{inspect(mode)}` mode.
    """
  end

  defp ensure_auto_demands!(_pad_description, _module) do
    :ok
  end

  defp build_pad_data(pad_description) do
    pad_description
    |> Map.delete(:accepted_formats_str)
    |> Map.merge(%{
      stream_format: nil,
      demand: nil,
      start_of_stream?: false,
      end_of_stream?: false,
      ref: pad_description.name,
      other_ref: nil,
      pid: nil
    })
    |> then(&struct!(Membrane.Element.PadData, &1))
  end

  @spec link_contexts(ctx_to_update :: t(), prev_ctx :: t(), next_ctx :: t()) :: t()
  def link_contexts(context, prev_context, next_context) do
    input_pad_data =
      context.pads.input
      |> Map.merge(%{
        other_demand_unit: prev_context.pads.output.demand_unit,
        other_ref: :output
      })

    output_pad_data =
      context.pads.output
      |> Map.merge(%{
        other_demand_unit: next_context.pads.input.demand_unit,
        other_ref: :input
      })

    Map.put(context, :pads, %{input: input_pad_data, output: output_pad_data})
  end

  @spec update_contexts(states(), (t() -> t())) :: states()
  def update_contexts(states, update_fun) do
    states
    |> Enum.map(fn {name, module, context, state} ->
      {name, module, update_fun.(context), state}
    end)
  end

  @spec before_incoming_action(t(), action :: any()) :: t()
  def before_incoming_action(context, {:stream_format, {:output, _stream_format}}) do
    context
  end

  def before_incoming_action(context, InternalAction.start_of_stream(:output)) do
    put_in(context.pads.input.start_of_stream?, true)
  end

  def before_incoming_action(context, {:end_of_stream, :output}) do
    put_in(context.pads.input.end_of_stream?, true)
  end

  def before_incoming_action(context, _action) do
    context
  end

  @spec after_incoming_action(t(), action :: action()) :: t()
  def after_incoming_action(context, {:stream_format, {:output, stream_format}}) do
    put_in(context.pads.input.stream_format, stream_format)
  end

  def after_incoming_action(context, _action) do
    context
  end

  @spec after_out_actions(t(), actions :: [action()]) :: t()
  def after_out_actions(context, actions) do
    Enum.reduce(actions, context, fn action, ctx -> after_out_action(ctx, action) end)
  end

  @spec after_out_action(t(), action :: action()) :: t()
  def after_out_action(context, {:stream_format, {:input, stream_format}}) do
    put_in(context.pads.input.stream_format, stream_format)
  end

  def after_out_action(context, {:stream_format, {:output, stream_format}}) do
    put_in(context.pads.output.stream_format, stream_format)
  end

  def after_out_action(context, InternalAction.start_of_stream(:output)) do
    put_in(context.pads.output.start_of_stream?, true)
  end

  def after_out_action(context, {:end_of_stream, :output}) do
    put_in(context.pads.output.end_of_stream?, true)
  end

  def after_out_action(context, InternalAction.playing()) do
    %{context | playback: :playing}
  end

  def after_out_action(context, _action) do
    context
  end
end
