defmodule Membrane.Integration.TestingFilter do
  use Membrane.Element.Base.Filter
  alias Membrane.Buffer

  def_source_pads source: {:always, :pull, :any}

  def_sink_pads sink: {:always, {:pull, demand_in: :buffers}, :any}

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
  def handle_demand(:source, size, _, _ctx, state) do
    {{:ok, demand: {:sink, state.demand_generator.(size)}, redemand: :source}, state}
  end

  @impl true
  def handle_process(:sink, %Buffer{payload: payload}, _, state) do
    {{:ok, buffer: {:source, %Buffer{payload: payload <> <<255>>}}}, state}
  end

  def default_demand_generator(demand), do: demand
end
