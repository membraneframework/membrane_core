defmodule Benchmark.Run.LinearFilter do
  @moduledoc false
  use Membrane.Filter

  alias Benchmark.Run.Reductions

  def_input_pad :input, accepted_format: _any, flow_control: :auto
  def_output_pad :output, accepted_format: _any, flow_control: :auto

  def_options number_of_reductions: [spec: integer()],
              generator: [spec: (integer() -> integer())]

  @impl true
  def handle_init(_ctx, opts) do
    workload_simulation = Reductions.prepare_desired_function(opts.number_of_reductions)
    state = %{buffers: [], workload_simulation: workload_simulation, generator: opts.generator}
    {[], state}
  end

  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    state.workload_simulation.()
    state = %{state | buffers: state.buffers ++ [buffer]}
    how_many_buffers_to_output = length(state.buffers) |> state.generator.()

    {buffers_to_output, rest_buffers} = Enum.split(state.buffers, how_many_buffers_to_output)
    state = %{state | buffers: rest_buffers}
    {[buffer: {:output, buffers_to_output}], state}
  end
end
