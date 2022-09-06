defmodule Membrane.Core.Element.DemandController do
  @moduledoc false

  # Module handling demands incoming through output pads.

  use Bunch

  alias Membrane.Core.{CallbackHandler, Message}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.{ActionHandler, PlaybackQueue, State, Toilet}
  alias Membrane.Element.CallbackContext
  alias Membrane.Pad

  require CallbackContext.Demand
  require Membrane.Core.Child.PadModel
  require Membrane.Logger

  @doc """
  Handles demand coming on an output pad. Updates demand value and executes `handle_demand` callback.
  """
  @spec handle_demand(Pad.ref_t(), non_neg_integer, State.t()) :: State.t()
  def handle_demand(pad_ref, size, state) do
    withl pad: {:ok, data} <- PadModel.get_data(state, pad_ref),
          playback: %State{playback: :playing} <- state do
      %{direction: :output, mode: :pull} = data
      do_handle_demand(pad_ref, size, data, state)
    else
      pad: {:error, :unknown_pad} ->
        # We've got a demand from already unlinked pad
        state

      playback: _playback ->
        PlaybackQueue.store(&handle_demand(pad_ref, size, &1), state)
    end
  end

  defp do_handle_demand(pad_ref, size, %{demand_mode: :auto} = data, state) do
    %{demand: old_demand, associated_pads: associated_pads} = data
    state = PadModel.set_data!(state, pad_ref, :demand, old_demand + size)

    if old_demand <= 0 do
      Enum.reduce(associated_pads, state, &send_auto_demand_if_needed/2)
    else
      state
    end
  end

  defp do_handle_demand(pad_ref, size, %{demand_mode: :manual} = data, state) do
    demand = data.demand + size
    data = %{data | demand: demand}
    state = PadModel.set_data!(state, pad_ref, data)

    if exec_handle_demand?(data) do
      require CallbackContext.Demand
      context = &CallbackContext.Demand.from_state(&1, incoming_demand: size)

      CallbackHandler.exec_and_handle_callback(
        :handle_demand,
        ActionHandler,
        %{
          split_continuation_arbiter: &exec_handle_demand?(PadModel.get_data!(&1, pad_ref)),
          context: context
        },
        [pad_ref, demand, data.other_demand_unit],
        state
      )
    else
      state
    end
  end

  @doc """
  Sends auto demand to an input pad if it should be sent.

  The demand should be sent when the current demand on the input pad is at most
  half of the demand request size and if there's positive demand on each of
  associated output pads.

  Also, the `demand_decrease` argument can be passed, decreasing the size of the
  demand on the input pad before proceeding to the rest of the function logic.
  """
  @spec send_auto_demand_if_needed(Pad.ref_t(), integer, State.t()) :: State.t()
  def send_auto_demand_if_needed(pad_ref, demand_decrease \\ 0, state) do
    data = PadModel.get_data!(state, pad_ref)

    %{
      demand: demand,
      toilet: toilet,
      associated_pads: associated_pads,
      auto_demand_size: demand_request_size
    } = data

    demand = demand - demand_decrease

    demand =
      if demand <= div(demand_request_size, 2) and auto_demands_positive?(associated_pads, state) do
        if toilet do
          Toilet.drain(toilet, demand_request_size - demand)
        else
          Membrane.Logger.debug_verbose(
            "Sending auto demand of size #{demand_request_size - demand} on pad #{inspect(pad_ref)}"
          )

          %{pid: pid, other_ref: other_ref} = data
          Message.send(pid, :demand, demand_request_size - demand, for_pad: other_ref)
        end

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
