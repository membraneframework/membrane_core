# A script providing a functionality to test performance of Membrane Core.

# Performance test is done with the following command:
# `mix run benchmark/run.exs <result file path>`
# Once performed, the results of the test will be saved as a binary file in the desired location.
# The benchmark consists of multiple test cases. Each test case can be of two types:
# * `:linear` - with a linear pipeline (consisting of a given number of filters, each of which has a single :input and a single :output pad)
# * `:with_branches` - with a pipeline having a single source, single sink and filters forming branches inbetween.
#
# `:linear` test case is parametrized with the following parameters:
# * `reductions` - number of reductions that will be performed in each `handle_buffer` invocation of each filter
# (it's a way to simulate the workload of the element)
# * `max_random` - an upper limit of the range of integers that can be randomly chosen.
# That parameters allows to simulate the stochastic nature of multimedia processing.
# * `number_of_filters` - number of lineary linked filters that the pipeline will consist of
# * `number_of_buffers` - number of buffers that will be generated by the source element before sending
# `:end_of_stream` event
# * `buffer_size` - size of each buffer, in bytes
#
# `:with_branches` test case is parametrized with the following parameters:
# `struct` - a list of tuples of form `{how_many_input_pads, how_many_output_pads}`, where
# `how_many_input_pads` and `how_many_output_pads` describe how many input
# pads and output pads, respectively, should filter at given level have.
# I.e. [{1, 3}, {1, 2}, {6, 1}] describes the following pipeline:
#
#                                                |---Filter_2_0 ---|
#                             |--- Filter_1_0 ---|                 |
#                             |                  |---Filter_2_1 ---|
#                             |                                    |
#                             |                  |---Filter_2_2 ---|
# Source ------ Filter_0_0 ---|--- Filter_1_1 ---|                 |---Filter_3_0 ------ Sink
#                             |                  |---Filter_2_3 ---|
#                             |                                    |
#                             |                  |---Filter_2_4 ---|
#                             |--- Filter_1_2 ---|                 |
#                                                |---Filter_2_5 ---|
#
#
# * `reductions` - number of reductions that will be performed in each `handle_buffer` invocation of each filter
# (it's a way to simulate the workload of the element)
# * `number_of_buffers` - number of buffers that will be generated by the source element before sending
# `:end_of_stream` event
# * `buffer_size` - size of each buffer, in bytes
#
# Test cases are specified with the @test_cases module attribute of the `Benchmark.Run` module.
# Each test case is performed multiple times - the number of repetitions is specified with the
# @how_many_tries attribute of the `Benchmark.Run` module.
# As a result of a test, a binary result file with an avaraged metrics gather during the test is created.
# `benchmark/comparse.exs` script can be used to compare result files.

defmodule Benchmark.Run do
  import Membrane.ChildrenSpec

  alias Membrane.Pad
  alias Benchmark.Run.BranchedFilter
  alias Benchmark.Run.LinearFilter
  alias Benchmark.Metric.{InProgressMemory, MessageQueuesLength, Time}

  require Logger
  require Membrane.RCPipeline
  require Membrane.Pad

  @test_cases [
    linear: [
      reductions: 1_000,
      max_random: 1,
      number_of_filters: 10,
      number_of_buffers: 500_000,
      buffer_size: 1
    ],
    linear: [
      reductions: 1_000,
      max_random: 1,
      number_of_filters: 100,
      number_of_buffers: 50_000,
      buffer_size: 1
    ],
    linear: [
      reductions: 1_000,
      max_random: 5,
      number_of_filters: 10,
      number_of_buffers: 50_000,
      buffer_size: 1
    ],
    with_branches: [
      struct: [{1, 3}, {3, 2}, {2, 1}],
      reductions: 100,
      number_of_buffers: 50_000,
      buffer_size: 1,
      max_random: 1
    ],
    with_branches: [
      struct: [{1, 2}, {1, 2}, {2, 1}, {2, 1}],
      reductions: 100,
      number_of_buffers: 500_000,
      buffer_size: 1,
      max_random: 10
    ]
  ]
  @how_many_tries 5
  # [ms]
  @test_timeout 300_000
  # the greater the factor is, the more unevenly distributed by the dispatcher will the buffers be
  @uneven_distribution_dispatcher_factor 2

  defp prepare_generator(max_random) do
    fn number_of_buffers ->
      how_many_needed = Enum.random(1..max_random)

      if number_of_buffers >= how_many_needed do
        how_many_to_output = Enum.random(1..max_random)
        min(number_of_buffers, how_many_to_output)
      else
        0
      end
    end
  end

  defp prepare_dispatcher() do
    fn how_many_pads, how_many_buffers_to_output ->
      max_buffers_per_pad =
        floor(@uneven_distribution_dispatcher_factor * how_many_buffers_to_output / how_many_pads)

      {distribution, how_many_buffers_for_last_pad} =
        Enum.map_reduce(1..(how_many_pads - 1)//1, how_many_buffers_to_output, fn _pad_no,
                                                                                  buffers_left ->
          how_many_buffers_per_pad = min(Enum.random(0..max_buffers_per_pad), buffers_left)
          {how_many_buffers_per_pad, buffers_left - how_many_buffers_per_pad}
        end)

      distribution = distribution ++ [how_many_buffers_for_last_pad]
      Enum.shuffle(distribution)
    end
  end

  defp source_buffers_generator(state, _size, params) do
    if state < params[:number_of_buffers] do
      {[
         buffer:
           {:output, %Membrane.Buffer{payload: :crypto.strong_rand_bytes(params[:buffer_size])}},
         redemand: :output
       ], state + 1}
    else
      {[end_of_stream: :output], state}
    end
  end

  defp prepare_pipeline(:linear, params) do
    source = %Membrane.Testing.Source{
      output: {1, &source_buffers_generator(&1, &2, params)}
    }

    Enum.reduce(
      1..params[:number_of_filters],
      child(:source, source),
      fn n, acc ->
        child(acc, String.to_atom("filter_#{n}"), %LinearFilter{
          number_of_reductions: params[:reductions],
          generator: prepare_generator(params[:max_random])
        })
      end
    )
    |> child(:sink, %Membrane.Testing.Sink{autodemand: true})
  end

  defp prepare_pipeline(:with_branches, params) do
    struct = params[:struct]

    source = %Membrane.Testing.Source{
      output: {1, &source_buffers_generator(&1, &2, params)}
    }

    initial_level = %{
      level: 0,
      unfinished_branches: [child(:source, source)],
      finished_branches: []
    }

    final_level =
      Enum.reduce(struct, initial_level, fn {how_many_input_pads, how_many_output_pads},
                                            current_level ->
        if rem(length(current_level.unfinished_branches), how_many_input_pads) != 0,
          do: raise("Wrong branched pipeline specification!")

        {newly_finished_branches, unfinished_branches} =
          add_filters_and_pads(current_level, how_many_input_pads, how_many_output_pads, params)

        %{
          level: current_level.level + 1,
          unfinished_branches: unfinished_branches,
          finished_branches: current_level.finished_branches ++ newly_finished_branches
        }
      end)

    if length(final_level.unfinished_branches) != 1,
      do: raise("Wrong branched pipeline specification!")

    branch_with_sink =
      Enum.at(final_level.unfinished_branches, 0) |> child(:sink, Membrane.Testing.Sink)

    [branch_with_sink] ++ final_level.finished_branches
  end

  defp add_filters_and_pads(level_description, how_many_input_pads, how_many_output_pads, params) do
    {newly_finished_branches_lists, unfinished_branches_lists} =
      Enum.chunk_every(level_description.unfinished_branches, how_many_input_pads)
      |> Enum.with_index()
      |> Enum.map(fn {group_of_branches, filter_no} ->
        [first_branch | rest_of_branches] = group_of_branches

        branch_ending_with_newly_added_element =
          first_branch
          |> via_in(Pad.ref(:input, 0))
          |> child(
            {:filter, level_description.level, filter_no},
            %BranchedFilter{
              number_of_reductions: params[:reductions],
              generator: prepare_generator(params[:max_random]),
              dispatcher: prepare_dispatcher()
            }
          )

        newly_finished_branches =
          Enum.with_index(rest_of_branches, 1)
          |> Enum.map(fn {branch, branch_index_in_group} ->
            branch
            |> via_in(Pad.ref(:input, branch_index_in_group))
            |> get_child({:filter, level_description.level, filter_no})
          end)

        unfinished_branches =
          Enum.map(0..(how_many_output_pads - 1), fn pad_no ->
            get_child({:filter, level_description.level, filter_no})
            |> via_out(Pad.ref(:output, pad_no))
          end)

        {[branch_ending_with_newly_added_element | newly_finished_branches], unfinished_branches}
      end)
      |> Enum.unzip()

    {List.flatten(newly_finished_branches_lists), List.flatten(unfinished_branches_lists)}
  end

  defp perform_test({test_type, params}) when test_type in [:linear, :with_branches] do
    spec = prepare_pipeline(test_type, params)

    time_meassurement = Time.start_meassurement()

    {:ok, _supervisor_pid, pipeline_pid} =
      Membrane.Pipeline.start(
        Benchmark.Run.Pipeline,
        monitoring_process: self(),
        spec: spec
      )

    children_pids = Membrane.Pipeline.call(pipeline_pid, :get_children_pids)

    in_progress_memory_meassurment = InProgressMemory.start_meassurement(children_pids)
    message_queues_length_meassurement = MessageQueuesLength.start_meassurement(children_pids)

    :ok =
      receive do
        :sink_eos -> :ok
      after
        @test_timeout ->
          raise "The test wasn't finished within the assumed timeout: #{@test_timeout} ms."
      end

    time = Time.stop_meassurement(time_meassurement)
    in_progress_memory = InProgressMemory.stop_meassurement(in_progress_memory_meassurment)

    message_queues_length =
      MessageQueuesLength.stop_meassurement(message_queues_length_meassurement)

    Membrane.Pipeline.terminate(pipeline_pid)

    %{
      Time => time,
      InProgressMemory => in_progress_memory,
      MessageQueuesLength => message_queues_length
    }
  end

  def start() do
    Enum.reduce(@test_cases, %{}, fn test_case, results_map ->
      results =
        for _try_number <- 1..@how_many_tries do
          perform_test(test_case)
        end

      averaged_results =
        Enum.reduce(results, %{}, fn test_case_results, aggregated_results_map ->
          Enum.reduce(test_case_results, aggregated_results_map, fn {metric_module, metric_value},
                                                                    aggregated_results_map ->
            Map.update(
              aggregated_results_map,
              metric_module,
              [metric_value],
              &(&1 ++ [metric_value])
            )
          end)
        end)
        |> Map.new(fn {metric_module, metric_result} ->
          {metric_module, metric_module.average(metric_result)}
        end)

      Map.put(results_map, test_case, averaged_results)
    end)
  end
end

output_filename = System.argv() |> Enum.at(0)
result_map = Benchmark.Run.start()
File.write!(output_filename, :erlang.term_to_binary(result_map))
