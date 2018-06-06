defmodule Membrane.Helper.Retry do
  @moduledoc """
  Helper for handling scenarios when some action should be repeated until it succeeds
  """
  alias Membrane.Time

  @type retry_option :: {:times, non_neg_integer()} | {:duration, Time.t()} | {:delay, Time.t()}

  @doc """
  Calls `fun` until function `arbiter` decides to stop
  """
  @spec retry(fun :: fun(), arbiter :: (any() -> :retry | :finish), params :: [retry_option()]) ::
          any()
  def retry(fun, arbiter, params) do
    times = params |> Keyword.get(:times, :infinity)
    duration = params |> Keyword.get(:duration, :infinity)
    delay = params |> Keyword.get(:delay, 0)
    fun |> do_retry(arbiter, times, duration, delay, 0, Time.monotonic_time())
  end

  defp do_retry(fun, arbiter, times, duration, delay, retries, init_time) do
    ret = fun.()

    case arbiter.(ret) do
      :finish ->
        ret

      :retry ->
        cond do
          times |> infOrGt(retries) &&
              duration |> infOrGt(Time.monotonic_time() - init_time + delay) ->
            :timer.sleep(delay |> Time.to_milliseconds())
            fun |> do_retry(arbiter, times, duration, delay, retries + 1, init_time)

          true ->
            ret
        end
    end
  end

  defp infOrGt(:infinity, _), do: true
  defp infOrGt(val, other), do: val > other
end
