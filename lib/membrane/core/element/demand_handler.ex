defmodule Membrane.Core.Element.DemandHandler do
  alias Membrane.Core
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
  use Membrane.Helper

  def handle_self_demand(pad_name, source, :set, buf_cnt, state) do
    {:ok, state} = set_sink_self_demand(pad_name, source, buf_cnt, state)

    supply_self_demand(pad_name, source, buf_cnt, state)
  end

  def handle_self_demand(pad_name, :self, :increase, buf_cnt, state) do
    {{:ok, total_buf_cnt}, state} =
      PadModel.get_and_update_data(
        pad_name,
        :self_demand,
        &{{:ok, &1 + buf_cnt}, &1 + buf_cnt},
        state
      )

    supply_self_demand(pad_name, :self, total_buf_cnt, state)
  end

  def check_and_handle_demands(pad_name, state) do
    demand = PadModel.get_data!(pad_name, :self_demand, state)

    self_demand_result =
      if demand > 0 do
        supply_self_demand(pad_name, :self, demand, state)
      else
        {:ok, state}
      end

    with {:ok, %State{type: :filter} = state} <- self_demand_result do
      PadModel.filter_names_by_data(%{direction: :source}, state)
      |> Helper.Enum.reduce_with(state, fn name, st ->
        DemandController.handle_demand(name, 0, st)
      end)
    else
      {:ok, %State{type: :sink} = state} -> {:ok, state}
    end
  end

  defp supply_self_demand(pad_name, source, buf_cnt, state) do
    pb_output =
      PadModel.get_and_update_data(
        pad_name,
        :buffer,
        &(&1 |> PullBuffer.take(buf_cnt)),
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
          #{inspect(source)} of size #{inspect(buf_cnt)}
          """,
          {:supply_demand, reason},
          state
        )
    end
  end

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

  defp handle_pullbuffer_output(pad_name, source, data, state) do
    data
    |> Helper.Enum.reduce_with(state, fn v, state ->
      do_handle_pullbuffer_output(pad_name, source, v, state)
    end)
  end

  defp do_handle_pullbuffer_output(pad_name, _source, {:event, e}, state),
    do: EventController.exec_handle_event(pad_name, e, state)

  defp do_handle_pullbuffer_output(pad_name, _source, {:caps, c}, state),
    do: CapsController.exec_handle_caps(pad_name, c, state)

  defp do_handle_pullbuffer_output(
         pad_name,
         source,
         {:buffers, buffers, buf_cnt},
         state
       ) do
    {:ok, state} = update_sink_self_demand(pad_name, source, &{:ok, &1 - buf_cnt}, state)

    BufferController.exec_buffer_handler(pad_name, source, buffers, state)
  end

  defp set_sink_self_demand(pad_name, :self, size, state),
    do: PadModel.set_data(pad_name, :self_demand, size, state)

  defp set_sink_self_demand(_pad_name, _src, _f, state), do: {:ok, state}

  defp update_sink_self_demand(pad_name, :self, f, state),
    do: PadModel.update_data(pad_name, :self_demand, f, state)

  defp update_sink_self_demand(_pad_name, _src, _f, state), do: {:ok, state}
end
