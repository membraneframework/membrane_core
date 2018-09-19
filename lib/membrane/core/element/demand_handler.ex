defmodule Membrane.Core.Element.DemandHandler do
  @moduledoc false
  # Module handling demands requested on source pads.

  alias Membrane.Core
  alias Membrane.Element.Pad
  alias Core.PullBuffer

  alias Core.Element.{
    BufferController,
    CapsController,
    DemandController,
    EventController,
    PadModel,
    State
  }

  require PadModel
  use Core.Element.Log
  use Bunch

  @doc """
  Updates demand on the given sink pad that should be supplied by future calls
  to `supply_demand/2` or `check_and_supply_demands/2`.
  """
  @spec update_demand(
          Pad.ref_t(),
          pos_integer,
          State.t()
        ) :: State.stateful_try_t()
  def update_demand(pad_ref, size, state) when is_integer(size) do
    state = PadModel.set_data!(pad_ref, :demand, size, state)
    {:ok, state}
  end

  def update_demand(pad_ref, size_fun, state) when is_function(size_fun) do
    PadModel.update_data(
      pad_ref,
      :demand,
      fn demand ->
        new_demand = size_fun.(demand)

        if new_demand < 0 do
          {:error, :negative_demand}
        else
          {:ok, new_demand}
        end
      end,
      state
    )
  end

  @doc """
  Based on the demand on the given pad takes PullBuffer contents
  and passes it to proper controllers.
  """
  @spec supply_demand(
          Pad.ref_t(),
          State.t()
        ) :: State.stateful_try_t()
  def supply_demand(pad_ref, state) do
    total_size = PadModel.get_data!(pad_ref, :demand, state)
    do_supply_demand(pad_ref, total_size, state)
  end

  @doc """
  Supplies the demand requested on the given sink pad, if there is any.

  In filters also triggers `handle_demand` callback when there is unsupplied demand
  on source pads
  """
  @spec check_and_supply_demands(Pad.ref_t(), State.t()) :: State.stateful_try_t()
  def check_and_supply_demands(pad_ref, state) do
    demand = PadModel.get_data!(pad_ref, :demand, state)

    supply_demand_res =
      if demand > 0 do
        do_supply_demand(pad_ref, demand, state)
      else
        {:ok, state}
      end

    case supply_demand_res do
      {:ok, %State{type: :filter} = state} ->
        is_pullbuffer_empty =
          pad_ref
          |> PadModel.get_data!(:buffer, state)
          |> PullBuffer.empty?()

        if is_pullbuffer_empty do
          {:ok, state}
        else
          PadModel.filter_refs_by_data(%{direction: :source}, state)
          |> Bunch.Enum.try_reduce(state, fn ref, st ->
            DemandController.handle_demand(ref, 0, st)
          end)
        end

      {:ok, %State{type: :sink} = state} ->
        {:ok, state}

      {{:error, reason}, state} ->
        {{:error, reason}, state}
    end
  end

  @spec do_supply_demand(Pad.ref_t(), pos_integer, State.t()) :: State.stateful_try_t()
  defp do_supply_demand(pad_ref, size, state) do
    pb_output =
      PadModel.get_and_update_data(
        pad_ref,
        :buffer,
        &(&1 |> PullBuffer.take(size)),
        state
      )

    with {{:ok, {_pb_status, data}}, state} <- pb_output,
         {:ok, state} <- handle_pullbuffer_output(pad_ref, data, state) do
      {:ok, state}
    else
      {{:error, reason}, state} ->
        warn_error(
          """
          Error while supplying demand on pad #{inspect(pad_ref)} of size #{inspect(size)}
          """,
          {:do_supply_demand, reason},
          state
        )
    end
  end

  @spec handle_pullbuffer_output(
          Pad.ref_t(),
          [{:event | :caps, any} | {:buffers, list, pos_integer}],
          State.t()
        ) :: State.stateful_try_t()
  defp handle_pullbuffer_output(pad_ref, data, state) do
    data
    |> Bunch.Enum.try_reduce(state, fn v, state ->
      do_handle_pullbuffer_output(pad_ref, v, state)
    end)
  end

  @spec do_handle_pullbuffer_output(
          Pad.ref_t(),
          {:event | :caps, any} | {:buffers, list, pos_integer},
          State.t()
        ) :: State.stateful_try_t()
  defp do_handle_pullbuffer_output(pad_ref, {:event, e}, state),
    do: EventController.exec_handle_event(pad_ref, e, state)

  defp do_handle_pullbuffer_output(pad_ref, {:caps, c}, state),
    do: CapsController.exec_handle_caps(pad_ref, c, state)

  defp do_handle_pullbuffer_output(
         pad_ref,
         {:buffers, buffers, size},
         state
       ) do
    state = PadModel.update_data!(pad_ref, :demand, &(&1 - size), state)

    BufferController.exec_buffer_handler(pad_ref, buffers, state)
  end
end
