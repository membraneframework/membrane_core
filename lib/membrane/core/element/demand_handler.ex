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
  Gets given amount of data from given sink pad's PullBuffer, passes it to proper
  controller, and checks if source demand has been suppplied. If not, than demand
  is assumed to be underestimated, and a zero-sized demand is sent to handle it
  again.
  """
  @spec handle_demand(
          Pad.name_t(),
          {:source, Pad.name_t()} | :self,
          :set | :increase,
          pos_integer,
          State.t()
        ) :: State.stateful_try_t()
  def handle_demand(pad_name, source, :set, size, state) do
    state = set_sink_demand(pad_name, source, size, state)
    supply_demand(pad_name, source, size, state)
  end

  def handle_demand(pad_name, :self, :increase, size, state) do
    {total_size, state} =
      PadModel.get_and_update_data!(
        pad_name,
        :demand,
        fn demand -> (demand + size) ~> {&1, &1} end,
        state
      )

    supply_demand(pad_name, :self, total_size, state)
  end

  @doc """
  Handles demands requested on given sink pad, if there are any.
  """
  @spec check_and_handle_demands(Pad.name_t(), State.t()) :: State.stateful_try_t()
  def check_and_handle_demands(pad_name, state) do
    demand = PadModel.get_data!(pad_name, :demand, state)

    if demand > 0 do
      supply_demand(pad_name, :self, demand, state)
    else
      {:ok, state}
    end
    |> case do
      {:ok, %State{type: :filter} = state} ->
        PadModel.filter_names_by_data(%{direction: :source}, state)
        |> Bunch.Enum.try_reduce(state, fn name, st ->
          DemandController.handle_demand(name, 0, st)
        end)

      {:ok, %State{type: :sink} = state} ->
        {:ok, state}

      {{:error, reason}, state} ->
        {{:error, reason}, state}
    end
  end

  @spec supply_demand(Pad.name_t(), {:source, Pad.name_t()} | :self, pos_integer, State.t()) ::
          State.stateful_try_t()
  defp supply_demand(pad_name, source, size, state) do
    pb_output =
      PadModel.get_and_update_data(
        pad_name,
        :buffer,
        &(&1 |> PullBuffer.take(size)),
        state
      )

    with {{:ok, {pb_status, data}}, state} <- pb_output,
         {:ok, state} <- handle_pullbuffer_output(pad_name, source, data, state) do
      :ok = send_dumb_demand_if_needed(source, pb_status, state)
      {:ok, state}
    else
      {{:error, reason}, state} ->
        warn_error(
          """
          Error while supplying demand on pad #{inspect(pad_name)} requested by
          #{inspect(source)} of size #{inspect(size)}
          """,
          {:supply_demand, reason},
          state
        )
    end
  end

  @spec send_dumb_demand_if_needed({:source, Pad.name_t()} | :self, :empty | :value, State.t()) ::
          :ok
  defp send_dumb_demand_if_needed(:self, _pb_status, _state),
    do: :ok

  defp send_dumb_demand_if_needed(
         {:source, src_name},
         pb_status,
         state
       ) do
    if pb_status != :empty && PadModel.get_data!(src_name, :demand, state) > 0 do
      debug(
        """
        handle_process did not produce expected amount of buffers, despite
        PullBuffer being not empty. Trying executing handle_demand again.
        """,
        state
      )

      send(self(), {:membrane_demand, [0, src_name]})
    end

    :ok
  end

  @spec handle_pullbuffer_output(
          Pad.name_t(),
          {:source, Pad.name_t()} | :self,
          [{:event | :caps, any} | {:buffers, list, pos_integer}],
          State.t()
        ) :: State.stateful_try_t()
  defp handle_pullbuffer_output(pad_name, source, data, state) do
    data
    |> Bunch.Enum.try_reduce(state, fn v, state ->
      do_handle_pullbuffer_output(pad_name, source, v, state)
    end)
  end

  @spec do_handle_pullbuffer_output(
          Pad.name_t(),
          {:source, Pad.name_t()} | :self,
          {:event | :caps, any} | {:buffers, list, pos_integer},
          State.t()
        ) :: State.stateful_try_t()
  defp do_handle_pullbuffer_output(pad_name, _source, {:event, e}, state),
    do: EventController.exec_handle_event(pad_name, e, state)

  defp do_handle_pullbuffer_output(pad_name, _source, {:caps, c}, state),
    do: CapsController.exec_handle_caps(pad_name, c, state)

  defp do_handle_pullbuffer_output(
         pad_name,
         source,
         {:buffers, buffers, size},
         state
       ) do
    state = update_sink_demand(pad_name, source, &(&1 - size), state)

    BufferController.exec_buffer_handler(pad_name, source, buffers, state)
  end

  @spec set_sink_demand(Pad.name_t(), {:source, Pad.name_t()} | :self, non_neg_integer, State.t()) ::
          State.t()
  defp set_sink_demand(pad_name, :self, size, state),
    do: PadModel.set_data!(pad_name, :demand, size, state)

  defp set_sink_demand(_pad_name, _src, _f, state), do: state

  @spec set_sink_demand(
          Pad.name_t(),
          {:source, Pad.name_t()} | :self,
          (non_neg_integer -> non_neg_integer),
          State.t()
        ) :: State.t()
  defp update_sink_demand(pad_name, :self, f, state),
    do: PadModel.update_data!(pad_name, :demand, f, state)

  defp update_sink_demand(_pad_name, _src, _f, state), do: state
end
