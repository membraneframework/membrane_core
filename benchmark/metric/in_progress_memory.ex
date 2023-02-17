defmodule Benchmark.Metric.InProgressMemory do
  @behaviour Benchmark.Metric

  @allowed_worsening_factor 0.5

  @impl true
  def assert(memory_samples, memory_samples_ref, test_case) do
    cumulative_memory = integrate(memory_samples)
    cumulative_memory_ref = integrate(memory_samples_ref)

    if cumulative_memory > cumulative_memory_ref * (1 + @allowed_worsening_factor),
      do:
        raise(
          "The memory performance has got worse! For test case: #{inspect(test_case, pretty: true)}
        the cumulative memory used to be: #{cumulative_memory_ref} MB and now it is: #{cumulative_memory} MB"
        )

    :ok
  end

  @impl true
  def average(memory_samples_from_multiple_tries) do
    memory_samples_from_multiple_tries
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list(&1))
    |> Enum.map(&(Enum.sum(&1) / (length(&1) * 1_000_000)))
  end

  defp integrate(memory_samples) do
    Enum.sum(memory_samples)
  end
end
