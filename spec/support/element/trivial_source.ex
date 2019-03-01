defmodule Membrane.Support.Element.TrivialSource do
  @moduledoc """
  This is minimal sample source element for use in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Membrane.Element.Base.Source
  use Bunch

  def_output_pad :output, caps: :any

  @impl true
  def handle_init(_options) do
    {:ok, %{cnt: 0}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, %Ctx.Demand{}, %{cnt: cnt} = state) do
    buffers =
      1..size
      |> Enum.map(fn cnt ->
        {:buffer,
         {:output, %Membrane.Buffer{payload: cnt |> Integer.digits() |> IO.iodata_to_binary()}}}
      end)

    {{:ok, buffers}, %{state | cnt: cnt + size}}
  end
end
