defmodule Membrane.Support.DemandsTest.Filter do
  @moduledoc false
  use Membrane.Filter

  alias Membrane.Buffer

  require Membrane.Logger

  def_output_pad :output, flow_control: :manual, accepted_format: _any

  def_input_pad :input, flow_control: :manual, demand_unit: :buffers, accepted_format: _any

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
    Membrane.Logger.warn("FILTER DEMADNING #{state.demand_generator.(size)}")

    {[demand: {:input, state.demand_generator.(size)}], state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{payload: payload}, _ctx, state) do
    state = Map.update(state, :i, 0, &(&1 + 1))
    {[buffer: {:output, %Buffer{payload: payload <> <<255>>}}, redemand: :output], state}
  end

  @spec default_demand_generator(integer()) :: integer()
  def default_demand_generator(demand), do: demand
end
