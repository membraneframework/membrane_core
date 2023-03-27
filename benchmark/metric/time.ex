defmodule Benchmark.Metric.Time do
  @behaviour Benchmark.Metric

  @(@tolerance_factor 0.15)

  @impl true
  def assert(time, time_ref, test_case) do
    if time > time_ref * (1 + @@tolerance_factor),
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

  @impl true
  def start_meassurement(_opts \\ nil) do
    :os.system_time(:milli_seconds)
  end

  @impl true
  def stop_meassurement(starting_time) do
    :os.system_time(:milli_seconds) - starting_time
  end
end
