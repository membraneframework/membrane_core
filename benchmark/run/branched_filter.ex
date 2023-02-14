defmodule Benchmark.Run.BranchedFilter do
  @moduledoc false
  use Membrane.Filter

  alias Benchmark.Run.Reductions

  def_input_pad :input, accepted_format: _any, availability: :on_request
  def_output_pad :output, accepted_format: _any, availability: :on_request

  def_options number_of_reductions: [spec: integer()]

  @impl true
  def handle_init(_ctx, opts) do
    workload_simulation = Reductions.prepare_desired_function(opts.number_of_reductions)
    {[], %{workload_simulation: workload_simulation}}
  end

  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    state.workload_simulation.()
    {[forward: buffer], state}
  end
end
