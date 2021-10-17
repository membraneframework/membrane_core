defmodule Membrane.Core.Element.DemandController do
  @moduledoc false

  # Module handling demands incoming through output pads.

  use Bunch

  alias Membrane.Core.CallbackHandler
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.{ActionHandler, State}
  alias Membrane.Element.CallbackContext
  alias Membrane.Pad

  require CallbackContext.Demand
  require Membrane.Core.Child.PadModel
  require Membrane.Logger

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
    {total_size, state} =
      state
      |> PadModel.get_and_update_data!(pad_ref, :demand, fn demand ->
        (demand + size) ~> {&1, &1}
      end)

    case PadModel.get_data!(state, pad_ref) do
      %{direction: :input} ->
        raise Membrane.PipelineError, """
        handle_demand can only be called for an output pad.
        pad_ref: #{inspect(pad_ref)}
        """

      %{end_of_stream?: true} ->
        Membrane.Logger.debug_verbose("""
        Demand controller: not executing handle_demand as :end_of_stream action has already been returned
        """)

        {:ok, state}

      %{demand: demand} when demand <= 0 ->
        Membrane.Logger.debug_verbose("""
        Demand controller: not executing handle_demand as demand is not greater than 0,
        demand: #{inspect(demand)}
        """)

        {:ok, state}

      %{other_demand_unit: unit} ->
        context = &CallbackContext.Demand.from_state(&1, incoming_demand: size)

        CallbackHandler.exec_and_handle_callback(
          :handle_demand,
          ActionHandler,
          %{context: context},
          [pad_ref, total_size, unit],
          state
        )
    end
  end
end
