defmodule Benchmark.Metric.MessageQueuesLength do
  @behaviour Benchmark.Metric

  @allowed_worsening_factor 0.5
  @sampling_period 100

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

  @impl true
  def start_meassurement(children_pids) do
    task =
      Task.async(fn ->
        do_loop([], children_pids)
      end)

    task
  end

  defp do_loop(acc, children_pids) do
    acc = acc ++ [meassure_queues_length(children_pids)]

    receive do
      :stop -> acc
    after
      @sampling_period -> do_loop(acc, children_pids)
    end
  end

  defp meassure_queues_length(children_pids) do
    Enum.map(children_pids, fn pid ->
      case :erlang.process_info(pid, :message_queue_len) do
        {:message_queue_len, message_queue_len} -> message_queue_len
        _other -> 0
      end
    end)
    |> Enum.sum()
  end

  @impl true
  def stop_meassurement(task) do
    send(task.pid, :stop)
    Task.await(task)
  end
end
