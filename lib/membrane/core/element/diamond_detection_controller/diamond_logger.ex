defmodule Membrane.Core.Element.DiamondDetectionController.DiamondLogger do
  @moduledoc false

  alias Membrane.Core.Element.DiamondDetectionController.PathInGraph
  alias Membrane.Core.Element.DiamondDetectionController.PathInGraph.Vertex

  require Membrane.Logger

  # logging a diamond is moved to the separate module due to testing

  @spec log_diamond(PathInGraph.t(), PathInGraph.t()) :: :ok
  def log_diamond(path_a, path_b) do
    from = List.last(path_a) |> Map.fetch!(:component_path)
    to = List.first(path_a) |> Map.fetch!(:component_path)

    Membrane.Logger.debug("""
    Two paths from element #{from} to #{to} were detected, in which all pads are operating in pull \
    mode. With such a pipeline configuration, the membrane flow control mechanism may stop demanding \
    buffers. If you are debugging such an issue, keep in mind that input pads with `flow_control: :auto` \
    demand data when there is a demand for data on ALL output pads with `flow_control: :auto`.

    The first path from #{from} to #{to} leads:
    #{inspect_path(path_a)}

    The second path from #{from} to #{to} leads:
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
