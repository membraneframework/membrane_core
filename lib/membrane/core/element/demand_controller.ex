defmodule Membrane.Core.Element.DemandController do
  @moduledoc false
  # Module handling demands incoming through source pads.

  alias Membrane.{Core, Element}
  alias Core.CallbackHandler
  alias Element.{CallbackContext, Pad}
  alias Core.Element.{ActionHandler, PadModel, State}
  require CallbackContext.Demand
  require PadModel
  use Core.Element.Log
  use Bunch

  @doc """
  Handles demand coming on a source pad. Updates demand value and executes `handle_demand` callback.
  """
  @spec handle_demand(Pad.ref_t(), non_neg_integer, State.t()) :: State.stateful_try_t()
  def handle_demand(pad_ref, size, state) do
    {total_size, state} =
      PadModel.get_and_update_data!(
        pad_ref,
        :demand,
        fn demand -> (demand + size) ~> {&1, &1} end,
        state
      )

    if exec_handle_demand?(pad_ref, state) do
      %{caps: caps, options: %{other_demand_in: demand_in}} = PadModel.get_data!(pad_ref, state)

      context = CallbackContext.Demand.from_state(state, caps: caps, incoming_demand: size)

      CallbackHandler.exec_and_handle_callback(
        :handle_demand,
        ActionHandler,
        %{split_cont_f: &exec_handle_demand?(pad_ref, &1)},
        [pad_ref, total_size, demand_in, context],
        state
      )
      |> or_warn_error("""
      Demand arrived from pad #{inspect(pad_ref)}, but error happened while
      handling it.
      """)
    else
      {:ok, state}
    end
  end

  @spec exec_handle_demand?(Pad.ref_t(), State.t()) :: boolean
  defp exec_handle_demand?(pad_ref, state) do
    case PadModel.get_data!(pad_ref, state) do
      %{eos: true} ->
        debug(
          """
          Demand handler: not executing handle_demand, as EoS has already been sent
          """,
          state
        )

        false

      %{demand: demand} when demand <= 0 ->
        debug(
          """
          Demand handler: not executing handle_demand, as demand is not greater than 0,
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
