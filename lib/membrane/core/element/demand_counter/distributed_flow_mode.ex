defmodule Membrane.Core.Element.DemandCounter.DistributedFlowMode do
  @moduledoc false

  alias Membrane.Core.Element.DemandCounter.DistributedAtomic
  alias Membrane.Core.Element.EffectiveFlowController

  @type t :: DistributedAtomic.t()
  @type flow_mode_value ::
          EffectiveFlowController.effective_flow_control() | :to_be_resolved

  @spec new(flow_mode_value) :: t
  def new(initial_value) do
    initial_value
    |> flow_mode_to_int()
    |> DistributedAtomic.new()
  end

  @spec get(t) :: flow_mode_value()
  def get(distributed_atomic) do
    distributed_atomic
    |> DistributedAtomic.get()
    |> int_to_flow_mode()
  end

  @spec put(t, flow_mode_value()) :: :ok
  def put(distributed_atomic, value) do
    value = flow_mode_to_int(value)
    DistributedAtomic.put(distributed_atomic, value)
  end

  defp int_to_flow_mode(0), do: :to_be_resolved
  defp int_to_flow_mode(1), do: :push
  defp int_to_flow_mode(2), do: :pull

  defp flow_mode_to_int(:to_be_resolved), do: 0
  defp flow_mode_to_int(:push), do: 1
  defp flow_mode_to_int(:pull), do: 2
end
