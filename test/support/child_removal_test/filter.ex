defmodule Membrane.Support.ChildRemovalTest.Filter do
  @moduledoc false
  use Membrane.Element.Base.Filter
  alias Membrane.Buffer

  def_output_pad :output, caps: :any, availability: :always

  def_input_pad :input, demand_unit: :buffers, caps: :any, availability: :always

  def_options demand_generator: [
                type: :function,
                spec: (pos_integer -> non_neg_integer),
                default: &__MODULE__.default_demand_generator/1
              ],
              target: [type: :pid]

  @impl true
  def handle_init(%{target: t} = opts) do
    send(t, {:filter_pid, self()})
    {:ok, opts}
  end

  @impl true
  def handle_demand(:output, size, _, _ctx, state) do
    {{:ok, demand: {:input, state.demand_generator.(size)}}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, _, %{target: t} = state) do
    send(t, :buffer_in_filter)
    {{:ok, buffer: {:output, %Buffer{payload: payload <> <<255>>}}, redemand: :output}, state}
  end

  @impl true
  def handle_shutdown(%{target: pid}) do
    send(pid, :element_shutting_down)
    :ok
  end

  def default_demand_generator(demand), do: demand
end
