defmodule Membrane.Testing.DataSource do
  @moduledoc """
  Testing Element for supplying data from list passed through options.
  """

  use Membrane.Source

  alias Membrane.{Buffer, Event}

  def_output_pad :output, caps: :any

  def_options data: [
                type: :payloads,
                spec: [Membrane.Payload.t()],
                description: "List of payloads that will be sent through `:output` pad."
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
