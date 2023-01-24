defmodule Membrane.PerformanceTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  @max_random 10
  defmodule Reductions do
    @function :erlang.date()
    @n1 1_00
    @n2 1_000_000
    defp setup_process(n) do
      parent = self()

      spawn(fn ->
        for _ <- 1..n do
          @function
        end

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

      fn ->
        for _ <- 1..n do
          @function
        end
      end
    end
  end

  defmodule Filter do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any

    def_options number_of_reductions: [spec: integer()],
                sleeping_time: [spec: integer()],
                generator: [spec: (integer() -> integer())]

    @impl true
    def handle_init(_ctx, opts) do
      reductions_func = Reductions.prepare_desired_function(opts.number_of_reductions)

      workload_simulation = fn ->
        Process.sleep(opts.sleeping_time)
        reductions_func.()
      end

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

  defp prepare_spec(
         how_many_filters,
         number_of_buffers,
         buffers_size,
         number_of_reductions,
         sleeping_time
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
      fn _n, acc ->
        child(acc, %Filter{
          number_of_reductions: number_of_reductions,
          sleeping_time: sleeping_time,
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

  test "performance" do
    start_time = :os.system_time(:milli_seconds)

    {:ok, _suprvisor_pid, pid} =
      Membrane.Testing.Pipeline.start_link(spec: prepare_spec(10, 50, 100, 100_000, 100))

    assert_end_of_stream(pid, :sink, :input, 100_000)
    test_time = :os.system_time(:milli_seconds) - start_time
    assert test_time < 10_000
  end
end
