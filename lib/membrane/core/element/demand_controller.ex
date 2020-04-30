defmodule Membrane.Core.Element.DemandController do
  @moduledoc false

  # Module handling demands incoming through output pads.

  use Bunch
  require Membrane.Logger
  require Membrane.Element.CallbackContext.Demand
  require Membrane.Core.Child.PadModel
  
  alias Membrane.Core.CallbackHandler
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.{ActionHandler, State}
  alias Membrane.Element.CallbackContext
  alias Membrane.Pad

  @doc """
  Handles demand coming on a output pad. Updates demand value and executes `handle_demand` callback.
  """
  @spec handle_demand(Pad.ref_t(), non_neg_integer, State.t()) ::
          State.stateful_try_t()
  def handle_demand(pad_ref, size, state) do
    if ignore?(pad_ref, state) do
      {:ok, state}
    else
      do_handle_demand(pad_ref, size, state)
    end
  end

  @spec ignore?(Pad.ref_t(), State.t()) :: boolean()
  defp ignore?(pad_ref, state), do: state.pads.data[pad_ref].mode == :push

  @spec do_handle_demand(Pad.ref_t(), non_neg_integer, State.t()) ::
          State.stateful_try_t()
  defp do_handle_demand(pad_ref, size, state) do
    PadModel.assert_data(state, pad_ref, %{direction: :output})

    {total_size, state} =
      state
      |> PadModel.get_and_update_data!(pad_ref, :demand, fn demand ->
        (demand + size) ~> {&1, &1}
      end)

    if exec_handle_demand?(pad_ref, state) do
      %{other_demand_unit: unit} = PadModel.get_data!(state, pad_ref)

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
        Demand controller: not executing handle_demand as EndOfStream has already been sent
        """)

        false

      %{demand: demand} when demand <= 0 ->
        Membrane.Logger.debug_verbose("""
        Demand controller: not executing handle_demand as demand is not greater than 0,
        demand: #{inspect(demand)}
        """)

        false

      _ ->
        true
    end
  end
end
