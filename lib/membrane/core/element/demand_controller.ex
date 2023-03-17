defmodule Membrane.Core.Element.DemandController do
  @moduledoc false

  # Module handling demands incoming through output pads.

  use Bunch

  alias Membrane.Buffer
  alias Membrane.Core.{CallbackHandler, Message}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.{ActionHandler, CallbackContext, DemandCounter, EffectiveFlowController, PlaybackQueue, State, Toilet}
  alias Membrane.Pad

  require Membrane.Core.Child.PadModel
  require Membrane.Logger

  # -----  NEW FUNCTIONALITIES

  @lacking_buffers_lowerbound 2000
  @lacking_buffers_upperbound 4000

  @spec increase_demand_counter_if_needed(Pad.ref(), State.t()) :: State.t()
  def increase_demand_counter_if_needed(pad_ref, state) do
    cond do
      PadModel.get_data!(state, pad_ref, :flow_control) == :manual ->
        do_increase_demand_counter_if_needed(:manual, pad_ref, state)

      EffectiveFlowController.pad_effective_flow_control(pad_ref, state) == :pull ->
        do_increase_demand_counter_if_needed(:auto_pull, pad_ref, state)

      true ->
        state
    end
  end

  defp do_increase_demand_counter_if_needed(:manual, _pad_ref, state) do
    state
  end

  defp do_increase_demand_counter_if_needed(:auto_pull, pad_ref, state) do
    %{
      demand_counter: demand_counter,
      lacking_buffers: lacking_buffers,
      associated_pads: associated_pads
    } = pad_data = PadModel.get_data!(state, pad_ref)

    if lacking_buffers < @lacking_buffers_lowerbound and
        Enum.all?(associated_pads, &DemandCounter.get(&1.demand_counter) > 0) do
      diff = @lacking_buffers_upperbound - lacking_buffers
      counter_value = DemandCounter.increase_get(demand_counter, diff)

      if counter_value - diff <= 0 do
        Message.send(pad_data.pid, :demand_counter_increased, pad_data.other_ref)
      end

      PadModel.set_data!(state, pad_ref, :lacking_buffers, @lacking_buffers_upperbound)
    else
      state
    end
  end

  @spec handle_ingoing_buffers(Pad.ref(), [Buffer.t()], State.t()) :: State.t()
  def handle_ingoing_buffers(pad_ref, buffers, state) do
    %{
      demand_unit: demand_unit,
      lacking_buffers: lacking_buffers
    } = PadModel.get_data!(state, pad_ref)

    buffers_size = Buffer.Metric.from_unit(demand_unit).buffers_size(buffers)
    PadModel.set_data!(state, pad_ref, :lacking_buffers, lacking_buffers - buffers_size)
  end

  @spec decrease_demand_counter_by_outgoing_buffers(Pad.ref(), [Buffer.t()], State.t()) :: State.t()
  def decrease_demand_counter_by_outgoing_buffers(pad_ref, buffers, state) do
    %{
      other_demand_unit: other_demand_unit,
      demand_counter: demand_counter
    } = PadModel.get_data!(state, pad_ref)

    buffers_size = Buffer.Metric.from_unit(other_demand_unit).buffers_size(buffers)
    demand_counter = DemandCounter.decrease(demand_counter, buffers_size)
    PadModel.set_data!(state, pad_ref, :demand_counter, demand_counter)
  end

  # ----- OLD FUNCTIONALITIES

  @doc """
  Handles demand coming on an output pad. Updates demand value and executes `handle_demand` callback.
  """
  @spec handle_demand(Pad.ref(), non_neg_integer, State.t()) :: State.t()
  def handle_demand(pad_ref, size, state) do
    withl pad: {:ok, data} <- PadModel.get_data(state, pad_ref),
          playback: %State{playback: :playing} <- state do
      if data.direction == :input,
        do: raise("Input pad cannot handle demand.")

      do_handle_demand(pad_ref, size, data, state)
    else
      pad: {:error, :unknown_pad} ->
        # We've got a demand from already unlinked pad
        state

      playback: _playback ->
        PlaybackQueue.store(&handle_demand(pad_ref, size, &1), state)
    end
  end

  defp do_handle_demand(pad_ref, size, %{flow_control: :auto} = data, state) do
    %{demand: old_demand, associated_pads: associated_pads} = data

    state = PadModel.set_data!(state, pad_ref, :demand, old_demand + size)

    if old_demand <= 0 do
      Enum.reduce(associated_pads, state, &send_auto_demand_if_needed/2)
    else
      state
    end
  end

  defp do_handle_demand(pad_ref, size, %{flow_control: :manual} = data, state) do
    demand = data.demand + size
    data = %{data | demand: demand}
    state = PadModel.set_data!(state, pad_ref, data)

    if exec_handle_demand?(data) do
      context = &CallbackContext.from_state(&1, incoming_demand: size)

      CallbackHandler.exec_and_handle_callback(
        :handle_demand,
        ActionHandler,
        %{
          split_continuation_arbiter: &exec_handle_demand?(PadModel.get_data!(&1, pad_ref)),
          context: context
        },
        [pad_ref, demand, data[:demand_unit]],
        state
      )
    else
      state
    end
  end

  defp do_handle_demand(_pad_ref, _size, %{flow_control: :push} = _data, state) do
    state
  end

  @doc """
  Sends auto demand to an input pad if it should be sent.

  The demand should be sent when the current demand on the input pad is at most
  half of the demand request size and if there's positive demand on each of
  associated output pads.
  """
  @spec send_auto_demand_if_needed(Pad.ref(), State.t()) :: State.t()
  def send_auto_demand_if_needed(pad_ref, state) do
    data = PadModel.get_data!(state, pad_ref)

    %{
      flow_control: :auto,
      demand: demand,
      toilet: toilet,
      associated_pads: associated_pads,
      auto_demand_size: demand_request_size
    } = data

    demand =
      if demand <= div(demand_request_size, 2) and
           (state.effective_flow_control == :push or
              auto_demands_positive?(associated_pads, state)) do
        Membrane.Logger.debug_verbose(
          "Sending auto demand of size #{demand_request_size - demand} on pad #{inspect(pad_ref)}"
        )

        %{pid: pid, other_ref: other_ref} = data
        Message.send(pid, :demand, demand_request_size - demand, for_pad: other_ref)

        if toilet, do: Toilet.drain(toilet, demand_request_size - demand)

        demand_request_size
      else
        Membrane.Logger.debug_verbose(
          "Not sending auto demand on pad #{inspect(pad_ref)}, pads data: #{inspect(state.pads_data)}"
        )

        demand
      end

    PadModel.set_data!(state, pad_ref, :demand, demand)
  end

  defp auto_demands_positive?(associated_pads, state) do
    Enum.all?(associated_pads, &(PadModel.get_data!(state, &1, :demand) > 0))
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
