
# A script providing a functionality to compare results of two performance tests.

# Comparison of two test results is done with the following command:
# `mix run benchmark/compare.exs <result file> <reference result file>`
# where the "result files" are the files generated with `mix run benchmark/run.exs` script.

# The following assertions are implemented:
#   * time assertion - the duration of the test might be no longer than 120% of the duration of the reference test.
#   * final memory assertion - the amount of memory used during the test, as meassured at the end of the test,
#   might be no greater than 120% of the memory used by the reference test.

defmodule Benchmark.Compare do
  require Logger
  defmodule PerformanceAssertions do
    @allowed_worsening_factor 0.5

    @spec assert_time(number(), number(), keyword(number())) :: nil
    def assert_time(time, time_ref, test_case) do
      if time > time_ref * (1 + @allowed_worsening_factor),
        do: raise("The time performance has got worse! For test case: #{inspect(test_case, pretty: true)} the test
          used to take: #{time_ref} ms and now it takes: #{time} ms")
    end

    @spec assert_final_memory(number(), number(), keyword(number())) :: nil
    def assert_final_memory(memory_samples, memory_samples_ref, test_case) do
      final_memory = Enum.at(memory_samples, -1)
      final_memory_ref = Enum.at(memory_samples_ref, -1)
      if final_memory > final_memory_ref * (1 + @allowed_worsening_factor),
        do:
          raise("The memory performance has got worse! For test case: #{inspect(test_case, pretty: true)}
          the final memory used to be: #{final_memory_ref} MB and now it is: #{final_memory} MB")
    end

    defp integrate(memory_samples) do
      Enum.sum(memory_samples)
    end

    @spec assert_cumulative_memory(number(), number(), keyword(number())) :: nil
    def assert_cumulative_memory(memory_samples, memory_samples_ref, test_case) do
      cumulative_memory = integrate(memory_samples)
      cumulative_memory_ref = integrate(memory_samples_ref)
      if cumulative_memory > cumulative_memory_ref * (1 + @allowed_worsening_factor),
        do:
          raise("The memory performance has got worse! For test case: #{inspect(test_case, pretty: true)}
          the cumulative memory used to be: #{cumulative_memory_ref} MB and now it is: #{cumulative_memory} MB")
    end
  end

  def run(results, ref_results) do
    if Map.keys(results) != Map.keys(ref_results),
      do: raise("Incompatible performance test result files!")

    Enum.each(Map.keys(results), fn test_case ->
      {time, memory_samples} = Map.get(results, test_case)
      {time_ref, memory_samples_ref} = Map.get(ref_results, test_case)

      Logger.debug(
        """

        TEST CASE:
        #{inspect(test_case, pretty: true)}

        TIME:
        #{time} [ms] vs #{time_ref} [ms]

        MEMORY_SAMPLES:
        #{inspect(memory_samples, pretty: true, limit: 10)} [MB] vs
        #{inspect(memory_samples_ref, pretty: true, limit: 10)} [MB]
        """
      )

      PerformanceAssertions.assert_time(time, time_ref, test_case)
      PerformanceAssertions.assert_final_memory(memory_samples, memory_samples_ref, test_case)
      PerformanceAssertions.assert_cumulative_memory(memory_samples, memory_samples_ref, test_case)
    end)

    :ok
  end
end
[results_filename, ref_results_filename] = System.argv() |> Enum.take(2)
results = File.read!(results_filename) |> :erlang.binary_to_term()
ref_results = File.read!(ref_results_filename) |> :erlang.binary_to_term()
Benchmark.Compare.run(results, ref_results)
