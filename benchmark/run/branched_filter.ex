defmodule Benchmark.Run.BranchedFilter do
  @moduledoc false
  use Membrane.Filter

  alias Benchmark.Run.Reductions

  def_input_pad :input, accepted_format: _any, availability: :on_request, flow_control: :auto
  def_output_pad :output, accepted_format: _any, availability: :on_request, flow_control: :auto

  def_options number_of_reductions: [spec: integer()],
              generator: [spec: (integer() -> integer())],
              dispatcher: [spec: (integer(), integer() -> [integer()])]

  @impl true
  def handle_init(_ctx, opts) do
    workload_simulation = Reductions.prepare_desired_function(opts.number_of_reductions)

    {[],
     %{
       buffers: [],
       workload_simulation: workload_simulation,
       generator: opts.generator,
       dispatcher: opts.dispatcher
     }}
  end

  @impl true
  def handle_buffer(_pad, buffer, ctx, state) do
    state = %{state | buffers: state.buffers ++ [buffer]}
    state.workload_simulation.()
    how_many_buffers_to_output = length(state.buffers) |> state.generator.()
    output_pads = Map.keys(ctx.pads) |> Enum.filter(&match?(Membrane.Pad.ref(:output, _id), &1))

    how_many_buffers_per_pad = state.dispatcher.(length(output_pads), how_many_buffers_to_output)

    {buffers_to_output, rest_buffers} = Enum.split(state.buffers, how_many_buffers_to_output)
    actions = prepare_actions(buffers_to_output, output_pads, how_many_buffers_per_pad)
    state = %{state | buffers: rest_buffers}
    {actions, state}
  end

  defp prepare_actions(buffers, output_pads, how_many_buffers_per_pad) do
    {actions, rest_of_buffers} =
      Enum.zip(output_pads, how_many_buffers_per_pad)
      |> Enum.map_reduce(buffers, fn {pad, how_many_buffers_per_pad}, buffers_left ->
        {buffers_for_this_pad, rest_buffers} = Enum.split(buffers_left, how_many_buffers_per_pad)
        action = {:buffer, {pad, buffers_for_this_pad}}
        {action, rest_buffers}
      end)

    if rest_of_buffers != [] do
      raise("The dispatcher function is working improperly!")
    end

    actions
  end

  @impl true
  def handle_end_of_stream(_pad, ctx, state) do
    all_input_pads_eos? =
      Enum.filter(ctx.pads, fn {_pad_ref, pad} -> pad.direction == :input end)
      |> Enum.all?(fn {_input_pad_ref, input_pad} -> input_pad.end_of_stream? == true end)

    if all_input_pads_eos? do
      output_pads_without_eos =
        Enum.filter(ctx.pads, fn {_pad_ref, pad} ->
          pad.end_of_stream? == false and pad.direction == :output
        end)
        |> Enum.map(fn {pad_ref, _pad} -> pad_ref end)

      actions = Enum.map(output_pads_without_eos, &{:end_of_stream, &1})
      {actions, state}
    else
      {[], state}
    end
  end
end
