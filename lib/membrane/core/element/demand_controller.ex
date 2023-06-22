defmodule Membrane.Core.Element.DemandController do
  @moduledoc false

  # Module handling changes in values of output pads atomic demand

  use Bunch

  alias __MODULE__.AutoFlowUtils

  alias Membrane.Buffer
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    AtomicDemand,
    DemandHandler,
    PlaybackQueue,
    State
  }

  alias Membrane.Pad

  require Membrane.Core.Child.PadModel
  require Membrane.Logger

  @spec snapshot_atomic_demand(Pad.ref(), State.t()) :: State.t()
  def snapshot_atomic_demand(pad_ref, state) do
    with {:ok, pad_data} <- PadModel.get_data(state, pad_ref),
         %State{playback: :playing} <- state do
      if pad_data.direction == :input,
        do: raise("cannot snapshot atomic counter in input pad")

      do_snapshot_atomic_demand(pad_data, state)
    else
      {:error, :unknown_pad} ->
        # We've got a :atomic_demand_increased message on already unlinked pad
        state

      %State{playback: :stopped} ->
        PlaybackQueue.store(&snapshot_atomic_demand(pad_ref, &1), state)
    end
  end

  defp do_snapshot_atomic_demand(
         %{flow_control: :auto} = pad_data,
         %{effective_flow_control: :pull} = state
       ) do
    %{
      atomic_demand: atomic_demand,
      associated_pads: associated_pads
    } = pad_data

    if AtomicDemand.get(atomic_demand) > 0 do
      AutoFlowUtils.auto_adjust_atomic_demand(associated_pads, state)
    else
      state
    end
  end

  defp do_snapshot_atomic_demand(%{flow_control: :manual} = pad_data, state) do
    with %{demand: demand, atomic_demand: atomic_demand}
         when demand <= 0 <- pad_data,
         atomic_demand_value
         when atomic_demand_value > 0 and atomic_demand_value > demand <-
           AtomicDemand.get(atomic_demand) do
      state =
        PadModel.update_data!(
          state,
          pad_data.ref,
          &%{
            &1
            | demand: atomic_demand_value,
              incoming_demand: atomic_demand_value - &1.demand
          }
        )

      DemandHandler.handle_redemand(pad_data.ref, state)
    else
      _other -> state
    end
  end

  defp do_snapshot_atomic_demand(_pad_data, state) do
    state
  end

  @doc """
  Decreases demand snapshot and atomic demand on the output by the size of outgoing buffers.
  """
  @spec decrease_demand_by_outgoing_buffers(Pad.ref(), [Buffer.t()], State.t()) :: State.t()
  def decrease_demand_by_outgoing_buffers(pad_ref, buffers, state) do
    pad_data = PadModel.get_data!(state, pad_ref)
    buffers_size = Buffer.Metric.from_unit(pad_data.demand_unit).buffers_size(buffers)

    demand = pad_data.demand - buffers_size
    atomic_demand = AtomicDemand.decrease(pad_data.atomic_demand, buffers_size)

    PadModel.set_data!(state, pad_ref, %{
      pad_data
      | demand: demand,
        atomic_demand: atomic_demand
    })
  end
end
