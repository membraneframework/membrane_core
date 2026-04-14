defmodule Membrane.Buffer.Metric.Count do
  @moduledoc """
  Implementation of `Membrane.Buffer.Metric` for the `:buffers` unit.

  > #### Deprecated {: .warning}
  > This module is deprecated. Use `Membrane.Core.Metric` functions with `:buffers` as the
  > `demand_unit` argument instead.
  """

  @behaviour Membrane.Buffer.Metric

  require Membrane.Logger

  @impl true
  def buffer_size_approximation() do
    ensure_deprecated_warning_printed()
    1
  end

  @impl true
  def init_manual_demand_size() do
    ensure_deprecated_warning_printed()
    0
  end

  @impl true
  def buffers_size(buffers) do
    ensure_deprecated_warning_printed()
    {:ok, length(buffers)}
  end

  @impl true
  def split_buffers(buffers, count, _first_consumed_buffer, _last_consumed_buffer) do
    ensure_deprecated_warning_printed()
    Enum.split(buffers, count)
  end

  @impl true
  def reduce_demand(demand, consumed) do
    ensure_deprecated_warning_printed()
    demand - consumed
  end

  defp ensure_deprecated_warning_printed() do
    if Process.get({__MODULE__, :deprecated_warned}) == nil do
      Membrane.Logger.warning(
        "#{__MODULE__} is deprecated. Use Membrane.Core.Metric with :buffers demand_unit instead."
      )

      Process.put({__MODULE__, :deprecated_warned}, true)
    end
  end
end
