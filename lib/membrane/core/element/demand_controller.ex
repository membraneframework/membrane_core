defmodule Membrane.Core.Element.DemandController do
  @moduledoc false

  # Module handling changes in values of output pads atomic demand

  use Bunch

  alias Membrane.Buffer
  alias Membrane.Element.PadData

  alias Membrane.Core.CallbackHandler
  alias Membrane.Core.Element.CallbackContext

  alias Membrane.Core.Element.{
    ActionHandler,
    AtomicDemand,
    AutoFlowController,
    ManualFlowController,
    PlaybackQueue,
    State
  }

  alias Membrane.Pad

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Logger

  @spec snapshot_atomic_demand(Pad.ref(), State.t()) :: State.t()
  def snapshot_atomic_demand(pad_ref, state) do
    with {:ok, pad_data} when not pad_data.end_of_stream? <- PadModel.get_data(state, pad_ref),
         %State{playback: :playing} <- state do
      if pad_data.direction == :input do
        raise Membrane.ElementError,
              "Cannot snapshot atomic counter in input pad #{inspect(pad_ref)}"
      end

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
    atomic_value = AtomicDemand.get(pad_data.atomic_demand)
    state = PadModel.set_data!(state, pad_data.ref, :demand, atomic_value)

    if atomic_value > 0 do
      state
      |> Map.update!(:satisfied_auto_output_pads, &MapSet.delete(&1, pad_data.ref))
      |> AutoFlowController.pop_queues_and_bump_demand()
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

      ManualFlowController.handle_redemand(pad_data.ref, state)
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

  @spec exec_handle_demand(Pad.ref(), State.t()) :: State.t()
  def exec_handle_demand(pad_ref, state) do
    with {:ok, pad_data} <- PadModel.get_data(state, pad_ref),
         true <- exec_handle_demand?(pad_data) do
      do_exec_handle_demand(pad_data, state)
    else
      _other -> state
    end
  end

  @spec do_exec_handle_demand(PadData.t(), State.t()) :: State.t()
  defp do_exec_handle_demand(pad_data, state) do
    context = &CallbackContext.from_state(&1, incoming_demand: pad_data.incoming_demand)

    CallbackHandler.exec_and_handle_callback(
      :handle_demand,
      ActionHandler,
      %{
        split_continuation_arbiter: &exec_handle_demand?(PadModel.get_data!(&1, pad_data.ref)),
        context: context
      },
      [pad_data.ref, pad_data.demand, pad_data.demand_unit],
      state
    )
  end

  defp exec_handle_demand?(%{end_of_stream?: true}) do
    Membrane.Logger.debug_verbose("""
    Demand controller: not executing handle_demand as :end_of_stream action has already been returned
    """)

    false
  end

  defp exec_handle_demand?(%{demand: demand}) when demand <= 0 do
    Membrane.Logger.debug_verbose("""
    Demand controller: not executing handle_demand as demand is not greater than 0,
    demand: #{inspect(demand)}
    """)

    false
  end

  defp exec_handle_demand?(_pad_data) do
    true
  end
end
