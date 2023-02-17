defmodule Benchmark.Metric.FinalMemory do
  @behaviour Benchmark.Metric

  @allowed_worsening_factor 0.5

  @impl true
  def assert(final_memory, final_memory_ref, test_case) do
    if final_memory > final_memory_ref * (1 + @allowed_worsening_factor),
      do:
        raise(
          "The memory performance has got worse! For test case: #{inspect(test_case, pretty: true)}
        the final memory used to be: #{final_memory_ref} MB and now it is: #{final_memory} MB"
        )

    :ok
  end

  @impl true
  def average(final_memory_samples) do
    Enum.sum(final_memory_samples) / (length(final_memory_samples) * 1_000_000)
  end
end
