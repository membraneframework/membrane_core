defmodule Membrane.Core.Element.DemandController do
  @moduledoc false
  # Module handling demands incoming through source pads.

  alias Membrane.{Core, Element}
  alias Core.CallbackHandler
  alias Element.Pad
  alias Core.Element.{ActionHandler, PadModel, State}
  require PadModel
  use Core.Element.Log
  use Membrane.Helper

  @doc """
  Updates demand and executes `handle_demand` callback.
  """
  @spec handle_demand(Pad.name_t(), non_neg_integer, State.t()) :: State.stateful_try_t()
  def handle_demand(pad_name, size, state) do
    {total_size, state} =
      PadModel.get_and_update_data!(
        pad_name,
        :demand,
        fn demand -> (demand + size) ~> {&1, &1} end,
        state
      )

    if exec_handle_demand?(pad_name, state) do
      %{caps: caps, options: %{other_demand_in: demand_in}} = PadModel.get_data!(pad_name, state)

      CallbackHandler.exec_and_handle_callback(
        :handle_demand,
        {ActionHandler, %{source: pad_name, split_cont_f: &exec_handle_demand?(pad_name, &1)}},
        [pad_name, total_size, demand_in],
        [caps: caps],
        state
      )
      |> or_warn_error("""
      Demand arrived from pad #{inspect(pad_name)}, but error happened while
      handling it.
      """)
    else
      {:ok, state}
    end
  end

  @spec exec_handle_demand?(Pad.name_t(), State.t()) :: boolean
  defp exec_handle_demand?(pad_name, state) do
    case PadModel.get_data!(pad_name, state) do
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
