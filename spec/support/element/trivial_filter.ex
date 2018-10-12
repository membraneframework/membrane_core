defmodule Membrane.Support.Element.TrivialFilter do
  @moduledoc """
  This is minimal sample filter element for use in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Membrane.Element.Base.Filter

  def_output_pads output: [caps: :any]

  def_input_pads input: [caps: :any, demand_unit: :buffers]

  @impl true
  def handle_init(_options) do
    {:ok, %{}}
  end

  @impl true
  def handle_demand(:output, size, _, %Ctx.Demand{}, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, %Membrane.Buffer{payload: payload}, %Ctx.Process{}, state) do
    {{:ok, buffer: {:output, %Membrane.Buffer{payload: payload <> <<255>>}}}, state}
  end
end
