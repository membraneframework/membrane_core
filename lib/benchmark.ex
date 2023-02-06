defmodule Mix.Tasks.Benchmark do
  @moduledoc """
  The module providing a mix task that allows to test performance of Membrane Core
  and compare the results of tests.

  ## Performing test
  Performance test is done with the following command:
  `mix benchmark start <result file path>`
  Once performed, the results of the test will be saved as a binary file in the desired location.
  The benchmark consists of multiple test cases. Each test case is parametrized with
  the following parameters:
  * `reductions` - number of reductions that will be performed during
  * `max_random` -
  * `number_of_filters` -
  * `number_of_buffers` -
  * `buffer_size` - size of each buffer, in bytes

  Test cases are specified with the @params_grid module attribute.
  Each test case is performed multiple times - the number of repetitions is specified with the
  @how_many_tries module's attribute.

  ## Comparing test results
  Comparison of two test results is done with the following command:
  `mix benchmark compare <result file> <reference result file>`
  where the "result files" are the files generated with `mix benchmark start` command.
  For information about the assertions that need to be fulfilled so that the test passes,
  see `PerformanceAssertions` module.
  """
  use Mix.Task

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  require Logger

  @how_many_tries 3
  @params_grid [
    [
      reductions: 100_000_000,
      max_random: 1,
      number_of_filters: 10,
      number_of_buffers: 50,
      buffer_size: 100_000
    ],
    [
      reductions: 10_000_000,
      max_random: 1,
      number_of_filters: 10,
      number_of_buffers: 500,
      buffer_size: 100_000
    ],
    [
      reductions: 10_000_000,
      max_random: 1,
      number_of_filters: 100,
      number_of_buffers: 50,
      buffer_size: 100_000
    ],
    [
      reductions: 100_000_000,
      max_random: 5,
      number_of_filters: 10,
      number_of_buffers: 50,
      buffer_size: 1
    ]
  ]

  defmodule Reductions do
    @moduledoc false

    @function :erlang.date()
    @n1 100
    @n2 1_000_000
    defp setup_process(n) do
      parent = self()

      spawn(fn ->
        Enum.each(1..n, fn _x -> @function end)
        send(parent, :erlang.process_info(self())[:reductions])
      end)
    end

    defp calculate do
      setup_process(@n1)

      r1 =
        receive do
          value -> value
        end

      setup_process(@n2)

      r2 =
        receive do
          value -> value
        end

      {r1, r2}
    end

    @spec prepare_desired_function(non_neg_integer()) :: (() -> any())
    def prepare_desired_function(how_many_reductions) do
      {r1, r2} = calculate()
      n = trunc((how_many_reductions - r2) / (r2 - r1) * (@n2 - @n1) + @n2)
      fn -> Enum.each(1..n, fn _x -> @function end) end
    end
  end

  defmodule Filter do
    @moduledoc false
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any

    def_options number_of_reductions: [spec: integer()],
                generator: [spec: (integer() -> integer())]

    @impl true
    def handle_init(_ctx, opts) do
      workload_simulation = Reductions.prepare_desired_function(opts.number_of_reductions)
      Process.send_after(self(), :collect, 10_000)
      state = %{buffers: [], workload_simulation: workload_simulation, generator: opts.generator}
      {[], state}
    end

    @impl true
    def handle_buffer(_pad, buffer, _ctx, state) do
      state.workload_simulation.()
      state = %{state | buffers: state.buffers ++ [buffer]}
      how_many_buffers_to_output = state.generator.(length(state.buffers))

      if how_many_buffers_to_output > 0 do
        [buffers_to_output | list_of_rest_buffers_lists] =
          Enum.chunk_every(state.buffers, how_many_buffers_to_output)

        buffers_to_output = Enum.map(buffers_to_output, &%Membrane.Buffer{payload: &1})
        rest_buffers = List.flatten(list_of_rest_buffers_lists)
        state = %{state | buffers: rest_buffers}
        {[buffer: {:output, buffers_to_output}], state}
      else
        {[], state}
      end
    end
  end

  defp prepare_spec(params) do
    Enum.reduce(
      1..params[:number_of_filters],
      child(%Membrane.Testing.Source{
        output:
          {1,
           fn state, _size ->
             if state < params[:number_of_buffers] do
               {[
                  buffer:
                    {:output,
                     %Membrane.Buffer{payload: :crypto.strong_rand_bytes(params[:buffer_size])}},
                  redemand: :output
                ], state + 1}
             else
               {[end_of_stream: :output], state}
             end
           end}
      }),
      fn n, acc ->
        child(acc, String.to_atom("filter_#{n}"), %Filter{
          number_of_reductions: params[:reductions],
          generator: fn number_of_buffers ->
            how_many_needed = Enum.random(1..params[:max_random])

            if number_of_buffers >= how_many_needed do
              how_many_to_output = Enum.random(1..params[:max_random])
              min(number_of_buffers, how_many_to_output)
            else
              0
            end
          end
        })
      end
    )
    |> child(:sink, %Membrane.Testing.Sink{autodemand: true})
  end

  defp is_finished?(pipeline_pid) do
    try do
      assert_end_of_stream(pipeline_pid, :sink, :input, 0)
    rescue
      _error -> false
    else
      _finished -> true
    end
  end

  defp meassure_memory(), do: :erlang.memory(:total)

  defp do_loop(pipeline_pid) do
    if is_finished?(pipeline_pid) do
      :ok
    else
      Process.sleep(1000)
      do_loop(pipeline_pid)
    end
  end

  defp perform_test(params) do
    initial_time = :os.system_time(:milli_seconds)
    initial_memory = meassure_memory()

    {:ok, _suprvisor_pid, pipeline_pid} =
      Membrane.Testing.Pipeline.start_link(spec: prepare_spec(params))

    do_loop(pipeline_pid)

    time = :os.system_time(:milli_seconds) - initial_time
    memory = meassure_memory() - initial_memory

    Membrane.Pipeline.terminate(pipeline_pid, blocking?: true)
    {time, memory}
  end

  @spec run([String.t()]) :: :ok
  def run(args_list)

  def run(["start", output_filename]) do
    Mix.Task.run("app.start")

    result_map =
      Enum.reduce(@params_grid, %{}, fn params, results_map ->
        results =
          for _try_number <- 1..@how_many_tries do
            perform_test(params)
          end

        avg_time = (Enum.unzip(results) |> elem(0) |> Enum.sum()) / length(results)
        avg_memory = (Enum.unzip(results) |> elem(1) |> Enum.sum()) / length(results)
        avg_memory_in_mb = avg_memory / 1_000_000
        Map.put(results_map, params, {avg_time, avg_memory_in_mb})
      end)

    File.write!(output_filename, :erlang.term_to_binary(result_map))
    :ok
  end

  defmodule PerformanceAssertions do
    @moduledoc """
    The module that delivers functions defining the conditions that need to be met so that the test passes.

    The following assertions are implemented:
    * time assertion - the duration of the test might be no longer than 120% of the duration of the reference test.
    * final memory assertion - the amount of memory used during the test, as meassured at the end of the test,
    might be no greater than 120% of the memory used by the reference test.
    """

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
          used to take: #{memory_ref} MB and now it takes: #{memory_ref} MB")
    end
  end

  def run(["compare", results_filename, ref_results_filename]) do
    results = File.read!(results_filename) |> :erlang.binary_to_term()
    ref_results = File.read!(ref_results_filename) |> :erlang.binary_to_term()

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
