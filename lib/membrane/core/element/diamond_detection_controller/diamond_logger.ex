defmodule Membrane.Core.Element.DiamondDetectionController.DiamondLogger do
  @moduledoc false

  alias Membrane.Core.Element.DiamondDetectionController.{
    DiamondLoggerImpl,
    PathInGraph
  }

  @callback log_diamond(PathInGraph.t(), PathInGraph.t()) :: :ok

  def log_diamond(path_a, path_b), do: impl().log_diamond(path_a, path_b)
  defp impl(), do: Application.get_env(:membrane_core, :diamond_logger, DiamondLoggerImpl)
end
