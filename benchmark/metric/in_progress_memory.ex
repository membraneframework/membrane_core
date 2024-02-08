defmodule Benchmark.Metric.InProgressMemory do
  @behaviour Benchmark.Metric

  @tolerance_factor 0.5
  @sampling_period 100

  @impl true
  def assert(memory_samples, memory_samples_ref, test_case) do
    cumulative_memory = integrate(memory_samples)
    cumulative_memory_ref = integrate(memory_samples_ref)

    if cumulative_memory > cumulative_memory_ref * (1 + @tolerance_factor),
      do:
        IO.warn(
          "The memory performance has got worse! For test case: #{inspect(test_case, pretty: true)}
        the cumulative memory used to be: #{cumulative_memory_ref} MB and now it is: #{cumulative_memory} MB"
        )

    :ok
  end

  defp integrate(memory_samples) do
    Enum.sum(memory_samples)
  end

  @impl true
  def average(memory_samples_from_multiple_tries) do
    memory_samples_from_multiple_tries
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list(&1))
    |> Enum.map(&(Enum.sum(&1) / (length(&1) * 1_000_000)))
  end

  @impl true
  def start_meassurement(_opts \\ nil) do
    Process.list() |> Enum.each(&:erlang.garbage_collect/1)

    task =
      Task.async(fn ->
        do_loop()
      end)

    task
  end

  defp do_loop(acc \\ []) do
    acc = [:erlang.memory(:total) | acc]

    receive do
      :stop -> Enum.reverse(acc)
    after
      @sampling_period -> do_loop(acc)
    end
  end

  @impl true
  def stop_meassurement(task) do
    send(task.pid, :stop)
    Task.await(task)
  end
end
