defmodule Membrane.Core.Element.DemandController do
  alias Membrane.{Core, Element}
  alias Core.{CallbackHandler, PullBuffer}
  alias Element.Context
  alias Core.Element.{ActionHandler, PadModel}
  require PadModel
  use Core.Element.Log
  use Membrane.Helper

  def fill_sink_pull_buffers(state) do
    PadModel.filter_data(%{direction: :sink}, state)
    |> Enum.filter(fn {_, %{mode: mode}} -> mode == :pull end)
    |> Helper.Enum.reduce_with(state, fn {pad_name, _pad_data}, st ->
      PadModel.update_data(pad_name, :buffer, &PullBuffer.fill/1, st)
    end)
    |> or_warn_error("Unable to fill sink pull buffers")
  end

  def handle_redemand(src_name, state) do
    handle_demand(src_name, 0, state)
  end

  def handle_demand(pad_name, size, state) do
    {{:ok, total_size}, state} =
      PadModel.get_and_update_data(
        pad_name,
        :demand,
        &{{:ok, &1 + size}, &1 + size},
        state
      )

    if exec_handle_demand?(pad_name, state) do
      %{caps: caps, options: %{other_demand_in: demand_in}} = PadModel.get_data!(pad_name, state)

      context = %Context.Demand{caps: caps}

      CallbackHandler.exec_and_handle_callback(
        :handle_demand,
        ActionHandler,
        %{source: pad_name, split_cont_f: &exec_handle_demand?(pad_name, &1)},
        [pad_name, total_size, demand_in, context],
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
