defmodule Membrane.Core.Element.DemandController do
  @moduledoc false

  # Module handling demands incoming through output pads.

  use Bunch

  alias Membrane.Core.{CallbackHandler, Message}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.{ActionHandler, State}
  alias Membrane.Element.CallbackContext
  alias Membrane.Pad

  require Membrane.Core.Child.PadModel
  require Membrane.Logger

  @doc """
  Handles demand coming on an output pad. Updates demand value and executes `handle_demand` callback.
  """
  @spec handle_demand(Pad.ref_t(), non_neg_integer, State.t()) ::
          State.stateful_try_t()
  def handle_demand(pad_ref, size, state) do
    %{direction: :output, demand_mode: demand_mode} = PadModel.get_data!(state, pad_ref)

    cond do
      ignore?(pad_ref, state) -> {:ok, state}
      demand_mode == :auto -> handle_auto_demand(pad_ref, size, state)
      true -> do_handle_demand(pad_ref, size, state)
    end
  end

  defp handle_auto_demand(pad_ref, size, state) do
    %{demand: old_demand, demand_pads: demand_pads} = PadModel.get_data!(state, pad_ref)
    state = PadModel.set_data!(state, pad_ref, :demand, old_demand + size)

    if old_demand <= 0 do
      {:ok, Enum.reduce(demand_pads, state, &check_auto_demand/2)}
    else
      {:ok, state}
    end
  end

  @spec check_auto_demand(Pad.ref_t(), State.t()) :: State.t()
  def check_auto_demand(pad_ref, state) do
    %{demand: demand, toilet: toilet, demand_pads: demand_pads} =
      data = PadModel.get_data!(state, pad_ref)

    demand_size = state.demand_size

    if demand <= div(demand_size, 2) and auto_demands_positive?(demand_pads, state) do
      if toilet do
        :atomics.sub(toilet, 1, demand_size - demand)
      else
        %{pid: pid, other_ref: other_ref} = data
        Message.send(pid, :demand, demand_size - demand, for_pad: other_ref)
      end

      PadModel.set_data!(state, pad_ref, :demand, demand_size)
    else
      state
    end
  end

  defp auto_demands_positive?(demand_pads, state) do
    Enum.all?(demand_pads, &(PadModel.get_data!(state, &1, :demand) > 0))
  end

  @spec ignore?(Pad.ref_t(), State.t()) :: boolean()
  defp ignore?(pad_ref, state), do: state.pads.data[pad_ref].mode == :push

  @spec do_handle_demand(Pad.ref_t(), non_neg_integer, State.t()) ::
          State.stateful_try_t()
  defp do_handle_demand(pad_ref, size, state) do
    {total_size, state} =
      state
      |> PadModel.get_and_update_data!(pad_ref, :demand, fn demand ->
        (demand + size) ~> {&1, &1}
      end)

    if exec_handle_demand?(pad_ref, state) do
      %{other_demand_unit: unit} = PadModel.get_data!(state, pad_ref)
      require CallbackContext.Demand
      context = &CallbackContext.Demand.from_state(&1, incoming_demand: size)

      CallbackHandler.exec_and_handle_callback(
        :handle_demand,
        ActionHandler,
        %{split_continuation_arbiter: &exec_handle_demand?(pad_ref, &1), context: context},
        [pad_ref, total_size, unit],
        state
      )
    else
      {:ok, state}
    end
  end

  @spec exec_handle_demand?(Pad.ref_t(), State.t()) :: boolean
  defp exec_handle_demand?(pad_ref, state) do
    case PadModel.get_data!(state, pad_ref) do
      %{end_of_stream?: true} ->
        Membrane.Logger.debug_verbose("""
        Demand controller: not executing handle_demand as :end_of_stream action has already been returned
        """)

        false

      %{demand: demand} when demand <= 0 ->
        Membrane.Logger.debug_verbose("""
        Demand controller: not executing handle_demand as demand is not greater than 0,
        demand: #{inspect(demand)}
        """)

        false

      _pad_data ->
        true
    end
  end
end
