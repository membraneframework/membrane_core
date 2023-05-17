defmodule Membrane.Core.Element.DemandCounter.DistributedFlowStatus do
  @moduledoc false

  alias Membrane.Core.Element.DemandCounter.DistributedAtomic
  alias Membrane.Core.Element.EffectiveFlowController

  @type t :: DistributedAtomic.t()
  @type value :: {:resolved, EffectiveFlowController.effective_flow_control()} | :to_be_resolved

  @spec new(value) :: t
  def new(initial_value) do
    initial_value
    |> flow_status_to_int()
    |> DistributedAtomic.new()
  end

  @spec get(t) :: value()
  def get(distributed_atomic) do
    distributed_atomic
    |> DistributedAtomic.get()
    |> int_to_flow_status()
  end

  @spec put(t, value()) :: :ok
  def put(distributed_atomic, value) do
    value = flow_status_to_int(value)
    DistributedAtomic.put(distributed_atomic, value)
  end

  defp int_to_flow_status(0), do: :to_be_resolved
  defp int_to_flow_status(1), do: {:resolved, :push}
  defp int_to_flow_status(2), do: {:resolved, :pull}

  defp flow_status_to_int(:to_be_resolved), do: 0
  defp flow_status_to_int({:resolved, :push}), do: 1
  defp flow_status_to_int({:resolved, :pull}), do: 2
end
