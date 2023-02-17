defmodule Benchmark.Metric.MessageQueuesLength do
  @behaviour Benchmark.Metric

  @allowed_worsening_factor 0.1

  @impl true
  def assert(queues_lengths, queues_lengths_ref, test_case) do
    cumulative_queues_length = integrate(queues_lengths)
    cumulative_queues_length_ref = integrate(queues_lengths_ref)

    if cumulative_queues_length >
         cumulative_queues_length_ref * (1 + @allowed_worsening_factor),
       do:
         raise(
           "The cumulative queues length has got worse! For test case: #{inspect(test_case, pretty: true)}
          the cumulative queues length to be: #{cumulative_queues_length_ref} and now it is: #{cumulative_queues_length}"
         )

    :ok
  end

  @impl true
  def average(queues_lengths_from_multiple_tries) do
    queues_lengths_from_multiple_tries
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list(&1))
    |> Enum.map(&(Enum.sum(&1) / length(&1)))
  end

  defp integrate(queues_lengths) do
    Enum.sum(queues_lengths)
  end
end
