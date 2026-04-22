defmodule Membrane.Buffer.Metric.Count do
  @moduledoc """
  Implementation of `Membrane.Buffer.Metric` for the `:buffers` unit.

  > #### Deprecated {: .warning}
  > This module is deprecated. The metric functionality has been moved to the internal API
  > of the Membrane Framework and is no longer accessible via this behaviour.
  """

  @behaviour Membrane.Buffer.Metric

  require Membrane.Logger

  @impl true
  def buffer_size_approximation() do
    ensure_deprecated_warning_printed()
    1
  end

  @impl true
  def buffers_size(buffers) do
    ensure_deprecated_warning_printed()
    length(buffers)
  end

  @impl true
  def split_buffers(buffers, count) do
    ensure_deprecated_warning_printed()
    Enum.split(buffers, count)
  end

  defp ensure_deprecated_warning_printed() do
    if Process.get({__MODULE__, :deprecated_warned}) == nil do
      Membrane.Logger.warning("""
      #{__MODULE__} is deprecated. The metric functionality has been moved to the internal \
      API of the Membrane Framework.
      """)

      Process.put({__MODULE__, :deprecated_warned}, true)
    end
  end
end
