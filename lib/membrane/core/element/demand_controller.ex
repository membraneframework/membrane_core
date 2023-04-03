defmodule Membrane.Core.Element.DemandController do
  @moduledoc false

  # Module handling demands incoming through output pads.

  use Bunch

  alias Membrane.Core.Element.DemandHandler
  alias Membrane.Element.PadData
  alias Membrane.Core.CallbackHandler
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    ActionHandler,
    CallbackContext,
    DemandCounter,
    DemandHandler,
    PlaybackQueue,
    State
  }

  alias Membrane.Pad

  require Membrane.Core.Child.PadModel
  require Membrane.Logger

  @lacking_buffers_lowerbound 2000
  @lacking_buffers_upperbound 4000

  @spec check_demand_counter(Pad.ref(), State.t()) :: State.t()
  def check_demand_counter(pad_ref, state) do
    with {:ok, pad} <- PadModel.get_data(state, pad_ref),
         %State{playback: :playing} <- state do
      if pad.direction == :input,
        do: raise("cannot check demand counter in input pad")

      do_check_demand_counter(pad, state)
    else
      {:error, :unknown_pad} ->
        # We've got a :demand_counter_increased message on already unlinked pad
        state

      %State{playback: :stopped} ->
        PlaybackQueue.store(&check_demand_counter(pad_ref, &1), state)
    end
  end

  defp do_check_demand_counter(
         %{flow_control: :auto} = pad_data,
         %{effective_flow_control: :pull} = state
       ) do
    %{
      demand_counter: demand_counter,
      associated_pads: associated_pads
    } = pad_data

    counter_value = demand_counter |> DemandCounter.get()

    # todo: maybe also check if pad_data.demand <= 0 ?
    if counter_value > 0 do
      # todo: optimize lopp below
      Enum.reduce(associated_pads, state, &increase_demand_counter_if_needed/2)
    else
      state
    end
  end

  defp do_check_demand_counter(%{flow_control: :manual} = pad_data, state) do
    DemandHandler.maybe_snapshot_demand_counter(pad_data.ref, state)
  end

  defp do_check_demand_counter(_pad_data, state) do
    state
  end

  @spec increase_demand_counter_if_needed(Pad.ref(), State.t()) :: State.t()
  def increase_demand_counter_if_needed(pad_ref, state) do
    pad_data = PadModel.get_data!(state, pad_ref)

    if increase_demand_counter?(pad_data, state) do
      diff = @lacking_buffers_upperbound - pad_data.lacking_buffers
      :ok = DemandCounter.increase(pad_data.demand_counter, diff)

      PadModel.set_data!(state, pad_ref, :lacking_buffers, @lacking_buffers_upperbound)
    else
      state
    end
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
    Membrane.Logger.warn("EXEC HANDLE DEMAND #{inspect(pad_data.ref)}")

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

  defp increase_demand_counter?(pad_data, state) do
    %{
      flow_control: flow_control,
      lacking_buffers: lacking_buffers,
      associated_pads: associated_pads
    } = pad_data

    flow_control == :auto and
      state.effective_flow_control == :pull and
      lacking_buffers < @lacking_buffers_lowerbound and
      Enum.all?(associated_pads, &demand_counter_positive?(&1, state))
  end

  defp demand_counter_positive?(pad_ref, state) do
    counter_value =
      PadModel.get_data!(state, pad_ref, :demand_counter)
      |> DemandCounter.get()

    counter_value > 0
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
