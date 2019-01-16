defmodule Membrane.Support.Element.DynamicFilter do
  @moduledoc """
  This is a mock filter with dynamic inputs for use in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Bunch
  use Membrane.Element.Base.Filter

  def_output_pads output: [caps: :any]

  def_input_pads input: [caps: :any, availability: :on_request, demand_unit: :buffers]

  def_options pid: [type: :pid]

  @impl true
  def handle_init(_options) do
    {:ok, %{pads: MapSet.new()}}
  end

  @impl true
  def handle_pad_added({:dynamic, :input, id}, _ctx, state) do
    {:ok, %{state | pads: state.pads |> MapSet.put(id)}}
  end

  @impl true
  def handle_pad_removed({:dynamic, :input, id}, _ctx, state) do
    {:ok, %{state | pads: state.pads |> MapSet.delete(id)}}
  end

  @impl true
  def handle_demand(_ref, size, _, %Ctx.Demand{}, state) do
    demand =
      state.in
      |> Enum.sort()
      |> Enum.take(1)
      ~>> ([id] -> [demand: {{:dynamic, :input, id}, size}])

    {{:ok, demand}, state}
  end

  @impl true
  def handle_process(_ref, %Membrane.Buffer{payload: _payload}, %Ctx.Process{}, state) do
    {:ok, state}
  end
end
