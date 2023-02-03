defmodule Mix.Tasks.Benchmark do
  alias ExUnit.FailuresManifest
  use Mix.Task

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

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
      fn -> Enum.map(1..n, fn _x -> @function end) end
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
    def handle_parent_notification({:get_memory, pid}, _ctx, state) do
      send(
        pid,
        {:memory_description,
         [
           heap_size: :erlang.process_info(self())[:heap_size],
           stack_size: :erlang.process_info(self())[:stack_size]
         ]}
      )

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

  defp meassure_memory_precisely(pipeline_pid) do
    Enum.reduce(1..@number_of_filters, 0, fn n, acc ->
      Membrane.Testing.Pipeline.execute_actions(pipeline_pid,
        notify_child: {String.to_atom("filter_#{n}"), {:get_memory, self()}}
      )

      memory_description =
        receive do
          {:memory_description, memory_description} -> memory_description
        end
      IO.inspect("RECEIVED")
      acc + memory_description[:heap_size] + memory_description[:stack_size]
    end)
  end

  defp meassure_memory_generaly() do
    :erlang.memory(:processes)
  end

  defp meassure_memory([mode: {:precise, pid}]), do: meassure_memory_precisely(pid)
  defp meassure_memory([mode: :general]), do: meassure_memory_generaly()

  defp do_loop(pipeline_pid, initial_time, initial_memory) do
    time = :os.system_time(:milli_seconds) - initial_time
    memory = meassure_memory(mode: :general) - initial_memory
    if is_finished?(pipeline_pid) do
      :ok
    else
      Process.sleep(1000)
      do_loop(pipeline_pid, initial_time, initial_memory)
    end
  end
  defp perform_test(reductions_number) do
    initial_time = :os.system_time(:milli_seconds)
    initial_memory = meassure_memory(mode: :general)

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

    Membrane.Pipeline.terminate(pipeline_pid, blocking?: true)
  end


  def run(_) do
    Mix.Task.run("app.start")
    for number_of_reductions <- [10_000_000],
        do: perform_test(number_of_reductions)
  end
end
