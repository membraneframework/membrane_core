defmodule Membrane.Support.Element.DynamicFilter do
  @moduledoc """
  This is a mock filter with dynamic inputs for use in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Membrane.Element.Base.Filter

  def_output_pads output: [caps: :any]

  def_input_pads input: [caps: :any, availability: :on_request, demand_unit: :buffers]

  @impl true
  def handle_init(_options) do
    {:ok, %{pads: MapSet.new()}}
  end

  @impl true
  def handle_pad_added(_ref, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_pad_removed(ref, _ctx, state) do
    send(self(), {:pad_removed, ref})
    {:ok, state}
  end

  @impl true
  def handle_demand(_ref, _size, _, %Ctx.Demand{}, state) do
    {:ok, state}
  end

  @impl true
  def handle_process(_ref, %Membrane.Buffer{payload: _payload}, %Ctx.Process{}, state) do
    {:ok, state}
  end
end
