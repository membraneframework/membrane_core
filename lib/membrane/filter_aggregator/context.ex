defmodule Membrane.FilterAggregator.Context do
  @moduledoc false

  def build_context!(name, module) do
    pad_descriptions = module.membrane_pads()
    pads = pad_descriptions |> MapSet.new(fn {k, _v} -> k end)

    expected_pads = [:input, :output] |> MapSet.new()

    unless MapSet.equal?(pads, expected_pads) do
      raise """
      Element #{inspect(module)} has unsupported pads.
      For more info on supported pads see the docs of Membrane.FilterAggregator
      #{inspect(module)}'s pads: : #{inspect(MapSet.to_list(pads))}
      """
    end

    pads_data =
      pad_descriptions
      |> Map.new(fn {name, description} -> {name, build_pad_data(description)} end)

    %{
      pads: pads_data,
      clock: nil,
      name: name,
      parent_clock: nil,
      playback_state: :stopped
    }
  end

  defp build_pad_data(pad_description) do
    pad_description
    |> Map.merge(%{
      accepted_caps: pad_description.caps,
      caps: nil,
      demand: 0,
      start_of_stream?: false,
      end_of_stream?: false,
      ref: pad_description.name,
      other_ref: nil,
      pid: nil
    })
    |> then(&struct!(Membrane.Element.PadData, &1))
  end

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

  def update_contexts(states, update_fun) do
    states
    |> Enum.map(fn {name, module, context, state} ->
      {name, module, update_fun.(context), state}
    end)
  end

  def before_incoming_action(context, {:buffer, {:output, buffers}}) do
    buf_size =
      Membrane.Buffer.Metric.from_unit(context.pads.input.demand_unit).buffers_size(
        buffers
        |> List.wrap()
      )

    put_in(context.pads.input.demand, context.pads.input.demand - buf_size)
  end

  def before_incoming_action(context, {:caps, {:output, _caps}}) do
    context
  end

  def before_incoming_action(context, {:start_of_stream, :output}) do
    put_in(context.pads.input.start_of_stream?, true)
  end

  def before_incoming_action(context, {:end_of_stream, :output}) do
    put_in(context.pads.input.end_of_stream?, true)
  end

  def before_incoming_action(context, {:demand, {:input, size}}) do
    current_demand = context.pads.output.demand
    put_in(context.pads.output.demand, current_demand + size)
  end

  def before_incoming_action(context, _action) do
    context
  end

  def after_incoming_action(context, {:caps, {:output, caps}}) do
    put_in(context.pads.input.caps, caps)
  end

  def after_incoming_action(context, _action) do
    context
  end

  def after_out_actions(context, actions) do
    Enum.reduce(actions, context, fn action, ctx -> after_out_action(ctx, action) end)
  end

  def after_out_action(context, {:buffer, {:output, buffers}}) do
    buf_size =
      Membrane.Buffer.Metric.from_unit(context.pads.output.other_demand_unit).buffers_size(
        buffers
        |> List.wrap()
      )

    put_in(context.pads.output.demand, context.pads.output.demand - buf_size)
  end

  def after_out_action(context, {:caps, {:input, caps}}) do
    put_in(context.pads.input.caps, caps)
  end

  def after_out_action(context, {:caps, {:output, caps}}) do
    put_in(context.pads.output.caps, caps)
  end

  def after_out_action(context, {:start_of_stream, :output}) do
    put_in(context.pads.output.start_of_stream?, true)
  end

  def after_out_action(context, {:end_of_stream, :output}) do
    put_in(context.pads.output.end_of_stream?, true)
  end

  def after_out_action(context, {:demand, {:input, size}}) do
    current_demand = context.pads.input.demand
    put_in(context.pads.input.demand, current_demand + size)
  end

  def after_out_action(context, action)
      when action in [
             :stopped_to_prepared,
             :prepared_to_playing,
             :playing_to_prepared,
             :prepared_to_stopped
           ] do
    pb_state =
      case action do
        :stopped_to_prepared -> :prepared
        :prepared_to_playing -> :playing
        :playing_to_prepared -> :prepared
        :prepared_to_stopped -> :stopped
      end

    %{context | playback_state: pb_state}
  end

  def after_out_action(context, _action) do
    context
  end
end