"""
The script providing a functionality to compare results of two performance tests.

Comparison of two test results is done with the following command:
`mix run benchmark/compare.exs <result file> <reference result file>`
where the "result files" are the files generated with `mix run benchmark/run.exs` script.

The following assertions are implemented:
  * time assertion - the duration of the test might be no longer than 120% of the duration of the reference test.
  * final memory assertion - the amount of memory used during the test, as meassured at the end of the test,
  might be no greater than 120% of the memory used by the reference test.
"""
defmodule Benchmark.Compare do
  require Logger
  defmodule PerformanceAssertions do
    @allowed_worsening_factor 0.2

    @spec assert_time(number(), number(), keyword(number())) :: nil
    def assert_time(time, time_ref, params) do
      if time > time_ref * (1 + @allowed_worsening_factor),
        do: raise("The time performance has got worse! For parameters: #{inspect(params)} the test
          used to take: #{time_ref} ms and now it takes: #{time} ms")
    end

    @spec assert_final_memory(number(), number(), keyword(number())) :: nil
    def assert_final_memory(memory, memory_ref, params) do
      if memory > memory_ref * (1 + @allowed_worsening_factor),
        do:
          raise("The memory performance has got worse! For parameters: #{inspect(params)} the test
          used to take: #{memory_ref} MB and now it takes: #{memory} MB")
    end
  end

  def run(results, ref_results) do
    if Map.keys(results) != Map.keys(ref_results),
      do: raise("Incompatible performance test result files!")

    Enum.each(Map.keys(results), fn params ->
      {time, memory} = Map.get(results, params)
      {time_ref, memory_ref} = Map.get(ref_results, params)

      Logger.debug(
        "PARAMS: #{inspect(params)} \n  time: #{time} ms vs #{time_ref} ms \n  memory: #{memory} MB vs #{memory_ref} MB"
      )

      PerformanceAssertions.assert_time(time, time_ref, params)
      PerformanceAssertions.assert_final_memory(memory, memory_ref, params)
    end)

    :ok
  end
end
[results_filename, ref_results_filename] = System.argv() |> Enum.take(2)
results = File.read!(results_filename) |> :erlang.binary_to_term()
ref_results = File.read!(ref_results_filename) |> :erlang.binary_to_term()
Benchmark.Compare.run(results, ref_results)
