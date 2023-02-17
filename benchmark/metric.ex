defmodule Benchmark.Metric do
  @moduledoc """
  A module defining a behaviour for metrics used in Membrane Core performance benchmarks.
  """

  @typedoc """
  A type describing a single meassurement of a given metric.

  """
  @type meassurement :: any

  @opaque meassurement_state :: any

  @doc """
  A function used to assert that the first meassurement is no worse than the second meassurement.
  """
  @callback assert(
              first_meassurement :: meassurement(),
              second_meassurement :: meassurement(),
              additional_params :: any
            ) ::
              :ok | no_return

  @doc """
  A function aggregating the list of meassurements gathered during multiple runs of the benchamark into a single
  meassurement.

  In case the first meassurement is worse than the second, the function should raise.
  """
  @callback average([meassurement]) :: meassurement

  @callback start_meassurement(opts :: any) :: meassurement_state
  @callback stop_meassurement(meassurement_state) :: meassurement
end
