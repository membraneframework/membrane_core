defmodule Membrane.Support.Element.TrivialSource do
  @moduledoc """
  This is minimal sample source element for use in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Membrane.Element.Base.Source
  use Bunch

  def_source_pads source: {:always, :pull, :any}

  @impl true
  def handle_init(_options) do
    {:ok, %{cnt: 0}}
  end

  @impl true
  def handle_demand(:source, size, :buffers, %Ctx.Demand{}, %{cnt: cnt} = state) do
    buffers =
      1..size
      |> Enum.map(fn cnt ->
        {:buffer,
         {:source, %Membrane.Buffer{payload: cnt |> Integer.digits() |> IO.iodata_to_binary()}}}
      end)

    {{:ok, buffers}, %{state | cnt: cnt + size}}
  end
end
