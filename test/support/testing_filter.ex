defmodule Membrane.Integration.TestingFilter do
  use Membrane.Element.Base.Filter
  alias Membrane.Buffer

  def_output_pads out: [caps: :any]

  def_input_pads in: [demand_in: :buffers, caps: :any]

  def_options demand_generator: [
                type: :function,
                spec: (pos_integer -> non_neg_integer),
                default: &__MODULE__.default_demand_generator/1
              ]

  @impl true
  def handle_init(opts) do
    {:ok, opts}
  end

  @impl true
  def handle_demand(:out, size, _, _ctx, state) do
    {{:ok, demand: {:in, state.demand_generator.(size)}, redemand: :out}, state}
  end

  @impl true
  def handle_process(:in, %Buffer{payload: payload}, _, state) do
    {{:ok, buffer: {:out, %Buffer{payload: payload <> <<255>>}}}, state}
  end

  def default_demand_generator(demand), do: demand
end
