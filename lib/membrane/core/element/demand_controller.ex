defmodule Membrane.Core.Element.DemandController do
  @moduledoc false

  # Module handling changes in values of output pads demand counters

  use Bunch

  alias __MODULE__.AutoFlowUtils

  alias Membrane.Buffer
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    DemandCounter,
    DemandHandler,
    PlaybackQueue,
    State
  }

  alias Membrane.Pad

  require Membrane.Core.Child.PadModel
  require Membrane.Logger

  @spec snapshot_demand_counter(Pad.ref(), State.t()) :: State.t()
  def snapshot_demand_counter(pad_ref, state) do
    with {:ok, pad_data} <- PadModel.get_data(state, pad_ref),
         %State{playback: :playing} <- state do
      if pad_data.direction == :input,
        do: raise("cannot snapshot demand counter in input pad")

      do_snapshot_demand_counter(pad_data, state)
    else
      {:error, :unknown_pad} ->
        # We've got a :demand_counter_increased message on already unlinked pad
        state

      %State{playback: :stopped} ->
        PlaybackQueue.store(&snapshot_demand_counter(pad_ref, &1), state)
    end
  end

  defp do_snapshot_demand_counter(
         %{flow_control: :auto} = pad_data,
         %{effective_flow_control: :pull} = state
       ) do
    %{
      demand_counter: demand_counter,
      associated_pads: associated_pads
    } = pad_data

    if DemandCounter.get(demand_counter) > 0 do
      AutoFlowUtils.auto_adjust_demand_counter(associated_pads, state)
    else
      state
    end
  end

  defp do_snapshot_demand_counter(%{flow_control: :manual} = pad_data, state) do
    with %{demand_snapshot: demand_snapshot, demand_counter: demand_counter}
         when demand_snapshot <= 0 <- pad_data,
         demand_counter_value
         when demand_counter_value > 0 and demand_counter_value > demand_snapshot <-
           DemandCounter.get(demand_counter) do
      state =
        PadModel.update_data!(
          state,
          pad_data.ref,
          &%{
            &1
            | demand_snapshot: demand_counter_value,
              incoming_demand: demand_counter_value - &1.demand_snapshot
          }
        )

      DemandHandler.handle_redemand(pad_data.ref, state)
    else
      _other -> state
    end
  end

  defp do_snapshot_demand_counter(_pad_data, state) do
    state
  end

  @doc """
  Decreases demand snapshot and demand counter on the output by the size of outgoing buffers.
  """
  @spec decrease_demand_by_outgoing_buffers(Pad.ref(), [Buffer.t()], State.t()) :: State.t()
  def decrease_demand_by_outgoing_buffers(pad_ref, buffers, state) do
    pad_data = PadModel.get_data!(state, pad_ref)

    demand_unit =
      case pad_data.flow_control do
        :push -> pad_data.other_demand_unit || :buffers
        _pull_or_auto -> pad_data.demand_unit
      end

    buffers_size = Buffer.Metric.from_unit(demand_unit).buffers_size(buffers)

    demand_snapshot = pad_data.demand_snapshot - buffers_size
    demand_counter = DemandCounter.decrease(pad_data.demand_counter, buffers_size)

    PadModel.set_data!(state, pad_ref, %{
      pad_data
      | demand_snapshot: demand_snapshot,
        demand_counter: demand_counter
    })
  end
end
