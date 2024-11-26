defmodule Membrane.Core.Element.DiamondDetectionController.DiamondLogger do
  @moduledoc false

  require Membrane.Logger

  alias Membrane.Core.Element.DiamondDetectionController.PathInGraph
  alias Membrane.Core.Element.DiamondDetectionController.PathInGraph.Vertex

  # logging a diamond is moved to the separate module due to testing

  @spec log_diamond(PathInGraph.t(), PathInGraph.t()) :: :ok
  def log_diamond(path_a, path_b) do
    Membrane.Logger.debug("""
    DIAMOND

    Path A:
    #{inspect_path(path_a)}

    Path B:
    #{inspect_path(path_b)}
    """)

    :ok
  end

  defp inspect_path(path) do
    path
    |> Enum.reverse()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map_join("\n", fn [%Vertex{} = from, %Vertex{} = to] ->
      """
      From #{from.component_path} via output pad #{inspect(from.output_pad_ref)} \
      to #{to.component_path} via input pad #{inspect(to.input_pad_ref)}.
      """
    end)
  end
end
