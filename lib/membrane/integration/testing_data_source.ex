defmodule Membrane.Element.TestingDataSource do
  @moduledoc """
  Testing Element for suplying data from Enumerable passed through options.
  """
  use Membrane.Element.Base.Source

  alias Membrane.{Buffer, Event}

  def_options data: [
                type: :buffers
              ]

  def_output_pads output: [
                    caps: :any
                  ]

  @impl true
  def handle_init(%__MODULE__{data: data}) do
    {:ok, %{data: data}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _context, %{data: data} = state) do
    case Enum.split(data, size) do
      {[], []} ->
        {{:ok, event: {:output, %Event.EndOfStream{}}}, state}

      {non_empty, rest} when is_list(non_empty) ->
        {{:ok, buffer: {:output, bufferize(data)}}, %{data: rest}}
    end
  end

  defp bufferize(data), do: Enum.map(data, &%Buffer{payload: &1})
end
