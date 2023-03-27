# A script providing a functionality to compare results of two performance tests.

# Comparison of two test results is done with the following command:
# `mix run benchmark/compare.exs <result file> <reference result file>`
# where the "result files" are the files generated with `mix run benchmark/run.exs` script.
# For information about the metric used, see the modules implementing `Benchmark.Metric` behaviour.

defmodule Benchmark.Compare do
  require Logger

  def run(results, ref_results, results_name, ref_results_name) do
    if Map.keys(results) != Map.keys(ref_results),
      do: raise("Incompatible performance test result files!")

    Enum.each(Map.keys(results), fn test_case ->
      test_case_results = Map.get(results, test_case)
      test_case_results_ref = Map.get(ref_results, test_case)

      results_str =
        Enum.map(Map.keys(test_case_results), fn metric_module ->
          """
          METRIC: #{metric_module}
          1. In #{results_name}:
          #{inspect(Map.get(test_case_results_ref, metric_module), pretty: true, limit: :infinity)}
          2. In #{refr_results_name}:
          #{inspect(Map.get(test_case_results, metric_module), pretty: true, limit: :infinity)}
          """
        end)
        |> Enum.join()

      Logger.debug("""
      TEST CASE:
      #{inspect(test_case, pretty: true, limit: :infinity)}

      #{results_str}

      """)

      Enum.each(Map.keys(test_case_results), fn metric_module ->
        metric_value = Map.get(test_case_results, metric_module)
        metric_value_ref = Map.get(test_case_results_ref, metric_module)
        metric_module.assert(metric_value, metric_value_ref, test_case)
      end)
    end)

    :ok
  end
end

[results_filename, ref_results_filename] = System.argv() |> Enum.take(2)
results = File.read!(results_filename) |> :erlang.binary_to_term()
ref_results = File.read!(ref_results_filename) |> :erlang.binary_to_term()
results_name = String.split(results_filename, "/") |> Enum.at(-1)
ref_results_name = String.split(ref_results_filename, "/") |> Enum.at(-1)
Benchmark.Compare.run(results, ref_results, results_name, ref_results_name)
