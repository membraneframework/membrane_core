defmodule Membrane.Support.Element.TrivialFilter do
  @moduledoc """
  This is minimal sample filter element for use in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Membrane.Element.Base.Filter

  def_output_pads out: [caps: :any]

  def_input_pads in: [caps: :any, demand_in: :buffers]

  @impl true
  def handle_init(_options) do
    {:ok, %{}}
  end

  @impl true
  def handle_demand(:out, size, _, %Ctx.Demand{}, state) do
    {{:ok, demand: {:in, size}}, state}
  end

  @impl true
  def handle_process(:in, %Membrane.Buffer{payload: payload}, %Ctx.Process{}, state) do
    {{:ok, buffer: {:out, %Membrane.Buffer{payload: payload <> <<255>>}}}, state}
  end
end
