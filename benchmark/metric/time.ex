defmodule Benchmark.Metric.Time do
  @behaviour Benchmark.Metric

  @allowed_worsening_factor 0.1

  @impl true
  def assert(time, time_ref, test_case) do
    if time > time_ref * (1 + @allowed_worsening_factor),
      do:
        raise(
          "The time performance has got worse! For test case: #{inspect(test_case, pretty: true)} the test
        used to take: #{time_ref} ms and now it takes: #{time} ms"
        )

    :ok
  end

  @impl true
  def average(times) do
    Enum.sum(times) / length(times)
  end
end
