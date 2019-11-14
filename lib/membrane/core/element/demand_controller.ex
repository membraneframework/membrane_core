defmodule Membrane.Core.Element.DemandController do
  @moduledoc false
  # Module handling demands incoming through output pads.

  alias Membrane.{Core, Element, Pad}
  alias Core.CallbackHandler
  alias Core.Child.PadModel
  alias Element.CallbackContext
  alias Core.Element.{ActionHandler, State}
  require CallbackContext.Demand
  require PadModel
  use Core.Element.Log
  use Bunch

  @doc """
  Handles demand coming on a output pad. Updates demand value and executes `handle_demand` callback.
  """
  @spec handle_demand(Pad.ref_t(), non_neg_integer, State.t()) ::
          State.stateful_try_t()
  def handle_demand(pad_ref, size, state) do
    if state.pads.data[pad_ref].mode == :pull do
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
        |> or_warn_error("""
        Demand arrived from pad #{inspect(pad_ref)}, but error happened while
        handling it.
        """)
      else
        {:ok, state}
      end
    else
      {:ok, state}
    end
  end

  @spec exec_handle_demand?(Pad.ref_t(), State.t()) :: boolean
  defp exec_handle_demand?(pad_ref, state) do
    case PadModel.get_data!(state, pad_ref) do
      %{end_of_stream?: true} ->
        debug(
          """
          Demand controller: not executing handle_demand as EndOfStream has already been sent
          """,
          state
        )

        false

      %{demand: demand} when demand <= 0 ->
        debug(
          """
          Demand controller: not executing handle_demand as demand is not greater than 0,
          demand: #{inspect(demand)}
          """,
          state
        )

        false

      _ ->
        true
    end
  end
end
