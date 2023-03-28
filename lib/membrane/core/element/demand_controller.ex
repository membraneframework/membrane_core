defmodule Membrane.Core.Element.DemandController do
  @moduledoc false

  # Module handling demands incoming through output pads.

  use Bunch

  alias Membrane.Element.PadData
  alias Membrane.Buffer
  alias Membrane.Core.{CallbackHandler, Message}
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    ActionHandler,
    CallbackContext,
    DemandCounter,
    PlaybackQueue,
    # ,
    State
    # Toilet
  }

  alias Membrane.Pad

  require Membrane.Core.Child.PadModel
  require Membrane.Logger

  # -----  NEW FUNCTIONALITIES

  @lacking_buffers_lowerbound 2000
  @lacking_buffers_upperbound 4000

  @handle_demand_loop_limit 2

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

    if counter_value > 0 do
      # todo: optimize lopp below
      Enum.reduce(associated_pads, state, &increase_demand_counter_if_needed/2)
    else
      state
    end
  end

  defp do_check_demand_counter(%{flow_control: :manual} = pad_data, state) do
    # counter_value = pad_data.demand_counter |> DemandCounter.get()
    # Membrane.Logger.debug("CHECKING DEMAND COUNTER #{counter_value}")
    # handle_manual_output_pad_demand(pad_data.ref, counter_value, state)

    snapshot_demand_counter(pad_data, state)
    |> exec_random_pad_handle_demand()
  end

  defp do_check_demand_counter(_pad_data, state) do
    state
  end

  @spec increase_demand_counter_if_needed(Pad.ref(), State.t()) :: State.t()
  def increase_demand_counter_if_needed(pad_ref, state) do
    pad_data = PadModel.get_data!(state, pad_ref)

    if increase_demand_counter?(pad_data, state) do
      diff = @lacking_buffers_upperbound - pad_data.lacking_buffers

      # IO.inspect(diff, label: "DEMAND CONTROLLER AUTO increasing counter by")

      :ok = DemandCounter.increase(pad_data.demand_counter, diff)

      PadModel.set_data!(state, pad_ref, :lacking_buffers, @lacking_buffers_upperbound)
    else
      state
    end
  end

  # @spec handle_manual_output_pad_demand(Pad.ref(), integer(), State.t()) :: State.t()
  # defp handle_manual_output_pad_demand(pad_ref, counter_value, state) when counter_value > 0 do
  #   with {:ok, pad_data} <- PadModel.get_data(state, pad_ref),
  #        %State{playback: :playing} <- state do
  #     pad_data =
  #       if counter_value > 0 and counter_value > pad_data.demand do
  #         %{
  #           pad_data
  #           | incoming_demand: counter_value - pad_data.demand,
  #             demand: counter_value,
  #             handle_demand_executed?: false
  #         }
  #       else
  #         pad_data
  #       end

  #     PadModel.set_data!(state, pad_ref, pad_data)
  #     |> exec_random_pad_handle_demand()
  #   else
  #     {:error, :unknown_pad} ->
  #       # We've got a :demand_counter_increased message on already unlinked pad
  #       state

  #     %State{playback: :stopped} ->
  #       PlaybackQueue.store(&check_demand_counter(pad_ref, &1), state)
  #   end
  # end

  # defp handle_manual_output_pad_demand(_pad_ref, _counter_value, state), do: state

  defp snapshot_demand_counter(pad_data, state) do
    d = pad_data.demand

    state =
      pad_data.demand_counter
      |> DemandCounter.get()
      |> case do
        counter_value when counter_value > 0 and counter_value > pad_data.demand ->
          PadModel.set_data!(state, pad_data.ref, %{
            pad_data
            | incoming_demand: counter_value - pad_data.demand,
              demand: counter_value,
              handle_demand_executed?: false
          })

        _counter_value ->
          state
      end

    pad_data = PadModel.get_data!(state, pad_data.ref)

    Membrane.Logger.warn(
      "PAD COUNTER DEMAND SNAPSHOT #{inspect(d)} -> #{inspect(pad_data.demand)}      (handle_demand_executed?: #{pad_data.handle_demand_executed?})"
    )

    state
  end

  @spec exec_random_pad_handle_demand(State.t()) :: State.t()
  def exec_random_pad_handle_demand(%{handle_demand_loop_counter: counter} = state)
      when counter >= @handle_demand_loop_limit do
    Membrane.Logger.warn("HANDLE DEMAND LOOP COUNTER LIMIT")

    Message.send(self(), :resume_handle_demand_loop)
    %{state | handle_demand_loop_counter: 0}
  end

  def exec_random_pad_handle_demand(state) do
    state = Map.update!(state, :handle_demand_loop_counter, &(&1 + 1))

    pads_to_draw =
      Map.values(state.pads_data)
      |> Enum.filter(fn
        %{
          direction: :output,
          flow_control: :manual,
          end_of_stream?: false,
          handle_demand_executed?: false,
          demand: demand
        } ->
          demand > 0

        _pad_data ->
          false
      end)

    # Membrane.Logger.warn("PADS TO DRAW #{inspect(pads_to_draw)}")

    case pads_to_draw do
      [] ->
        Membrane.Logger.warn("NO PAD TO DRAW")

        with {:ok, data} <- PadModel.get_data(state, :output) do
          Membrane.Logger.warn(
            "PAD :output handle_demand_executed? #{data.handle_demand_executed?} demand #{data.demand}"
          )
        end

        %{state | handle_demand_loop_counter: 0}

      pads_to_draw ->
        Enum.random(pads_to_draw)
        |> exec_handle_demand(state)
    end
  end

  @spec redemand(Pad.ref(), State.t()) :: State.t()
  def redemand(pad_ref, state) do
    with {:ok, %{direction: :output, flow_control: :manual} = pad_data} <-
           PadModel.get_data(state, pad_ref) do
      state = snapshot_demand_counter(pad_data, state)
      pad_data = PadModel.get_data!(state, pad_ref)

      if exec_handle_demand?(pad_data) do
        exec_handle_demand(pad_data, state)
      else
        state
      end
    else
      {:ok, %{direction: :input}} ->
        raise "Cannot redemand input pad #{inspect(pad_ref)}."

      {:ok, %{flow_control: mode}} when mode != :manual ->
        raise "Cannot redemand pad #{inspect(pad_ref)} because it has #{inspect(mode)} flow control."

      {:error, :unknown_pad} ->
        state
    end
  end

  @spec exec_handle_demand(PadData.t(), State.t()) :: State.t()
  defp exec_handle_demand(pad_data, state) do
    Membrane.Logger.warn("EXEC HANDLE DEMAND #{inspect(pad_data.ref)}")

    context = &CallbackContext.from_state(&1, incoming_demand: pad_data.incoming_demand)

    state = PadModel.set_data!(state, pad_data.ref, :handle_demand_executed?, true)

    state =
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

    check_demand_counter(pad_data.ref, state)
  end

  defp increase_demand_counter?(pad_data, state) do
    %{
      flow_control: flow_control,
      lacking_buffers: lacking_buffers,
      associated_pads: associated_pads
    } = pad_data

    Membrane.Logger.warn("\n\nDUPA #{inspect(flow_control == :auto)}")
    Membrane.Logger.warn("DUPA #{inspect(state.effective_flow_control)}")
    Membrane.Logger.warn("DUPA #{inspect(lacking_buffers)}")

    Membrane.Logger.warn(
      "DUPA #{inspect(Enum.all?(associated_pads, &demand_counter_positive?(&1, state)))}"
    )

    flow_control == :auto and
      state.effective_flow_control == :pull and
      lacking_buffers < @lacking_buffers_lowerbound and
      Enum.all?(associated_pads, &demand_counter_positive?(&1, state))
  end

  defp demand_counter_positive?(pad_ref, state) do
    PadModel.get_data!(state, pad_ref, :demand_counter)
    |> DemandCounter.get()
    |> then(&(&1 > 0))
  end

  # @spec handle_ingoing_buffers(Pad.ref(), [Buffer.t()], State.t()) :: State.t()
  # def handle_ingoing_buffers(pad_ref, buffers, state) do
  #   %{
  #     demand_unit: demand_unit,
  #     lacking_buffers: lacking_buffers
  #   } = PadModel.get_data!(state, pad_ref)

  #   buffers_size = Buffer.Metric.from_unit(demand_unit).buffers_size(buffers)
  #   PadModel.set_data!(state, pad_ref, :lacking_buffers, lacking_buffers - buffers_size)
  # end

  @spec decrease_demand_counter_by_outgoing_buffers(Pad.ref(), [Buffer.t()], State.t()) ::
          State.t()
  def decrease_demand_counter_by_outgoing_buffers(pad_ref, buffers, state) do
    pad_data = PadModel.get_data!(state, pad_ref)
    buffers_size = Buffer.Metric.from_unit(pad_data.other_demand_unit).buffers_size(buffers)

    pad_demand = pad_data.demand - buffers_size
    demand_counter = DemandCounter.decrease(pad_data.demand_counter, buffers_size)

    PadModel.update_data!(
      state,
      pad_ref,
      &%{&1 | demand: pad_demand, demand_counter: demand_counter}
    )
  end

  # ----- OLD FUNCTIONALITIES

  # @doc """
  # Handles demand coming on an output pad. Updates demand value and executes `handle_demand` callback.
  # """
  # @spec handle_demand(Pad.ref(), non_neg_integer, State.t()) :: State.t()
  # def handle_demand(pad_ref, size, state) do
  #   withl pad: {:ok, data} <- PadModel.get_data(state, pad_ref),
  #         playback: %State{playback: :playing} <- state do
  #     if data.direction == :input,
  #       do: raise("Input pad cannot handle demand.")

  #     do_handle_demand(pad_ref, size, data, state)
  #   else
  #     pad: {:error, :unknown_pad} ->
  #       # We've got a demand from already unlinked pad
  #       state

  #     playback: _playback ->
  #       PlaybackQueue.store(&handle_demand(pad_ref, size, &1), state)
  #   end
  # end

  # defp do_handle_demand(pad_ref, size, %{flow_control: :auto} = data, state) do
  #   %{demand: old_demand, associated_pads: associated_pads} = data

  #   state = PadModel.set_data!(state, pad_ref, :demand, old_demand + size)

  #   if old_demand <= 0 do
  #     Enum.reduce(associated_pads, state, &send_auto_demand_if_needed/2)
  #   else
  #     state
  #   end
  # end

  # defp do_handle_demand(pad_ref, size, %{flow_control: :manual} = data, state) do
  #   demand = data.demand + size
  #   data = %{data | demand: demand}
  #   state = PadModel.set_data!(state, pad_ref, data)

  #   if exec_handle_demand?(data) do
  #     context = &CallbackContext.from_state(&1, incoming_demand: size)

  #     CallbackHandler.exec_and_handle_callback(
  #       :handle_demand,
  #       ActionHandler,
  #       %{
  #         split_continuation_arbiter: &exec_handle_demand?(PadModel.get_data!(&1, pad_ref)),
  #         context: context
  #       },
  #       [pad_ref, demand, data[:demand_unit]],
  #       state
  #     )
  #   else
  #     state
  #   end
  # end

  # defp do_handle_demand(_pad_ref, _size, %{flow_control: :push} = _data, state) do
  #   state
  # end

  # @doc """
  # Sends auto demand to an input pad if it should be sent.

  # The demand should be sent when the current demand on the input pad is at most
  # half of the demand request size and if there's positive demand on each of
  # associated output pads.
  # """
  # @spec send_auto_demand_if_needed(Pad.ref(), State.t()) :: State.t()
  # def send_auto_demand_if_needed(pad_ref, state) do
  #   data = PadModel.get_data!(state, pad_ref)

  #   %{
  #     flow_control: :auto,
  #     demand: demand,
  #     toilet: toilet,
  #     associated_pads: associated_pads,
  #     auto_demand_size: demand_request_size
  #   } = data

  #   demand =
  #     if demand <= div(demand_request_size, 2) and
  #          (state.effective_flow_control == :push or
  #             auto_demands_positive?(associated_pads, state)) do
  #       Membrane.Logger.debug_verbose(
  #         "Sending auto demand of size #{demand_request_size - demand} on pad #{inspect(pad_ref)}"
  #       )

  #       %{pid: pid, other_ref: other_ref} = data
  #       Message.send(pid, :demand, demand_request_size - demand, for_pad: other_ref)

  #       if toilet, do: Toilet.drain(toilet, demand_request_size - demand)

  #       demand_request_size
  #     else
  #       Membrane.Logger.debug_verbose(
  #         "Not sending auto demand on pad #{inspect(pad_ref)}, pads data: #{inspect(state.pads_data)}"
  #       )

  #       demand
  #     end

  #   PadModel.set_data!(state, pad_ref, :demand, demand)
  # end

  # defp auto_demands_positive?(associated_pads, state) do
  #   Enum.all?(associated_pads, &(PadModel.get_data!(state, &1, :demand) > 0))
  # end

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
