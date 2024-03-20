defmodule Membrane.Core.Element.DemandController do
  @moduledoc false

  # Module handling changes in values of output pads atomic demand

  use Bunch

  alias __MODULE__.AutoFlowUtils

  alias Membrane.Buffer

  alias Membrane.Core.Element.{
    AtomicDemand,
    DemandHandler,
    PlaybackQueue,
    State
  }

  alias Membrane.Pad

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Logger

  # problem potencjalnie jest taki, ze np handlujac redemand robimy snapshot auto demandow, co moze powodowac faworyzacje auto > manual
  # wiec zrobilem zawsze zaczynanie od manual, potem auto
  # 1) nie wiem czy jest to problem, bo:
  #  - resume demand loop counter
  #  - zawsze ogranicza nas bedac w petli to co jest w kolejkach

  @spec consume_queues(State.t()) :: State.t()
  def consume_queues(state) do
    # if Enum.random([1, 2]) == 1 do
    #   state
    #   |> snapshot_pads_to_snapshot()
    #   |> DemandHandler.handle_delayed_demands()
    # else
    #   state
    #   |> DemandHandler.handle_delayed_demands()
    #   |> snapshot_pads_to_snapshot()
    # end
    state
    |> DemandHandler.handle_delayed_demands()
    |> snapshot_pads_to_snapshot()
  end

  @spec snapshot_pads_to_snapshot(State.t()) :: State.t()
  def snapshot_pads_to_snapshot(state) do
    Enum.reduce(state.pads_to_snapshot, state, fn pad_ref, state ->
      if MapSet.member?(state.pads_to_snapshot, pad_ref) do
        state = Map.update!(state, :pads_to_snapshot, &MapSet.delete(&1, pad_ref))
        snapshot_atomic_demand(pad_ref, state)
      else
        state
      end
    end)
  end

  @spec snapshot_atomic_demand(Pad.ref(), State.t()) :: State.t()
  def snapshot_atomic_demand(pad_ref, state) do
    with {:ok, pad_data} when not pad_data.end_of_stream? <- PadModel.get_data(state, pad_ref),
         %State{playback: :playing} <- state do
      if pad_data.direction == :input,
        do: raise("cannot snapshot atomic counter in input pad")

      do_snapshot_atomic_demand(pad_data, state)
    else
      {:ok, %{end_of_stream?: true}} ->
        Membrane.Logger.debug_verbose(
          "Skipping snapshot of pad #{inspect(pad_ref)}, because it has flag :end_of_stream? set to true"
        )

        state

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
    if AtomicDemand.get(pad_data.atomic_demand) > 0 do
      state
      |> Map.update!(:satisfied_auto_output_pads, &MapSet.delete(&1, pad_data.ref))
      |> AutoFlowUtils.pop_queues_and_bump_demand()
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

      false = state.delay_consuming_queues?

      # jesli w handle_redemand robimy consume_queues, to bedziemy mieli rekurencje tutaj bardzo niefajna
      # plus, czy to czasem nie popsuje pętli z counterem?
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
    {decrease_result, atomic_demand} = AtomicDemand.decrease(pad_data.atomic_demand, buffers_size)

    with {:decreased, new_value} when new_value <= 0 <- decrease_result,
         %{flow_control: :auto} <- pad_data do
      Map.update!(state, :satisfied_auto_output_pads, &MapSet.put(&1, pad_ref))
    else
      _other -> state
    end
    |> PadModel.set_data!(pad_ref, %{
      pad_data
      | demand: demand,
        atomic_demand: atomic_demand
    })
  end
end
