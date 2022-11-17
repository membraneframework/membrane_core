defmodule Membrane.Support.DemandsTest.Filter do
  @moduledoc false
  use Membrane.Filter

  alias Membrane.Buffer

  def_output_pad :output, accepted_format: _any

  def_input_pad :input, demand_unit: :buffers, accepted_format: _any

  def_options demand_generator: [
                spec: (pos_integer -> non_neg_integer),
                default: &__MODULE__.default_demand_generator/1
              ]

  @impl true
  def handle_init(_ctx, opts) do
    {[], opts}
  end

  @impl true
  def handle_demand(:output, size, _unit, _ctx, state) do
    {[demand: {:input, state.demand_generator.(size)}], state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, _ctx, state) do
    {[buffer: {:output, %Buffer{payload: payload <> <<255>>}}, redemand: :output], state}
  end

  @spec default_demand_generator(integer()) :: integer()
  def default_demand_generator(demand), do: demand
end
