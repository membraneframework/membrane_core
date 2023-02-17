defmodule Benchmark.Run.Reductions do
  @moduledoc false

  @function :erlang.date()
  @n1 100
  @n2 1_000_000
  defp meassure(n) do
    task =
      Task.async(fn ->
        Enum.each(1..n, fn _x -> @function end)
        :erlang.process_info(self())[:reductions]
      end)

    Task.await(task)
  end

  defp calculate do
    r1 = meassure(@n1)
    r2 = meassure(@n2)

    {r1, r2}
  end

  @spec prepare_desired_function(non_neg_integer()) :: (() -> any())
  def prepare_desired_function(how_many_reductions) do
    {r1, r2} = calculate()
    n = trunc((how_many_reductions - r2) / (r2 - r1) * (@n2 - @n1) + @n2)
    fn -> Enum.each(1..n, fn _x -> @function end) end
  end
end
