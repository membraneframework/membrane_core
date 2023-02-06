defmodule Mix.Tasks.Benchmark do
  alias ExUnit.FailuresManifest
  use Mix.Task
  require Logger
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  @how_many_tries 3

  @max_random 1
  @number_of_filters 20
  @number_of_buffers 50
  @buffers_size 100_000

  defmodule Reductions do
    @function :erlang.date()
    @n1 100
    @n2 1_000_000
    defp setup_process(n) do
      parent = self()

      spawn(fn ->
        Enum.each(1..n, fn _ -> @function end)
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

  def prepare_spec(
        how_many_filters,
        number_of_buffers,
        buffers_size,
        number_of_reductions
      ) do
    Enum.reduce(
      1..how_many_filters,
      child(%Membrane.Testing.Source{
        output:
          {1,
           fn state, _size ->
             if state < number_of_buffers do
               {[
                  buffer:
                    {:output, %Membrane.Buffer{payload: :crypto.strong_rand_bytes(buffers_size)}},
                  redemand: :output
                ], state + 1}
             else
               {[end_of_stream: :output], state}
             end
           end}
      }),
      fn n, acc ->
        child(acc, String.to_atom("filter_#{n}"), %Filter{
          number_of_reductions: number_of_reductions,
          generator: fn number_of_buffers ->
            how_many_needed = Enum.random(1..@max_random)

            if number_of_buffers >= how_many_needed do
              how_many_to_output = Enum.random(1..@max_random)
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

  defp perform_test(reductions_number) do
    initial_time = :os.system_time(:milli_seconds)
    initial_memory = meassure_memory()

    {:ok, _suprvisor_pid, pipeline_pid} =
      Membrane.Testing.Pipeline.start_link(
        spec:
          prepare_spec(
            @number_of_filters,
            @number_of_buffers,
            @buffers_size,
            reductions_number
          )
      )

    do_loop(pipeline_pid, initial_time, initial_memory)

    time = :os.system_time(:milli_seconds) - initial_time
    memory = meassure_memory() - initial_memory

    Membrane.Pipeline.terminate(pipeline_pid, blocking?: true)
    {time, memory}
  end

  @params_grid [10_000_000]

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
        avg_memory_in_mb = avg_memory/1_000_000
        Map.put(results_map, params, {avg_time, avg_memory_in_mb})
      end)

    File.write!(output_filename, :erlang.term_to_binary(result_map))
  end

  @worsening_factor 0.2

  def run(["compare", results_filename, ref_results_filename]) do
    results = File.read!(results_filename) |> :erlang.binary_to_term()
    ref_results = File.read!(ref_results_filename) |> :erlang.binary_to_term()

    if Map.keys(results) != Map.keys(ref_results),
      do: raise("Incompatible performance test result files!")

    Enum.each(Map.keys(results), fn params ->
      {time, memory} = Map.get(results, params)
      {time_ref, memory_ref} = Map.get(ref_results, params)
      Logger.debug("PARAMS: #{inspect(params)} \n  time: #{time} ms vs #{time_ref} ms \n  memory: #{memory} MB vs #{memory_ref} MB")
      if time > time_ref * (1 + @worsening_factor),
        do:
          raise(
            "The time performance has got worse! For parameters: #{inspect(params)} the test
             used to take: #{inspect(time_ref)} ms and now it takes: #{inspect(time)} ms"
          )
      if memory > memory_ref * (1 + @worsening_factor),
      do:
        raise(
          "The memory performance has got worse! For parameters: #{inspect(params)} the test
            used to take: #{inspect(memory_ref)} MB and now it takes: #{inspect(memory_ref)} MB"
        )
    end)
  end
end
