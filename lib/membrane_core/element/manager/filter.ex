defmodule Membrane.Element.Manager.Filter do
  @moduledoc false
  # Module responsible for managing filter elements - executing callbacks and
  # handling actions.

  use Membrane.Element.Manager.Log
  use Membrane.Element.Manager.Common
  import Membrane.Element.Pad, only: [is_pad_name: 1]
  alias Membrane.Element.Manager.{ActionExec, State, Common}
  alias Membrane.PullBuffer
  use Membrane.Helper

  # Private API

  def handle_action({:buffer, {pad_name, buffers}}, cb, _params, state)
      when is_pad_name(pad_name) do
    ActionExec.send_buffer(pad_name, buffers, cb, state)
  end

  def handle_action({:caps, {pad_name, caps}}, _cb, _params, state)
      when is_pad_name(pad_name) do
    ActionExec.send_caps(pad_name, caps, state)
  end

  def handle_action({:forward, data}, cb, params, state)
      when cb in [:handle_caps, :handle_event, :handle_process] do
    {action, dir} =
      case {cb, params} do
        {:handle_process, _} -> {:buffer, :source}
        {:handle_caps, _} -> {:caps, :source}
        {:handle_event, %{direction: :sink}} -> {:event, :source}
        {:handle_event, %{direction: :source}} -> {:event, :sink}
      end

    pads = state |> State.get_pads_data(dir) |> Map.keys()

    pads
    |> Helper.Enum.reduce_with(state, fn pad, st ->
      handle_action({action, {pad, data}}, cb, params, st)
    end)
  end

  def handle_action({:demand, pad_name}, :handle_demand, params, state)
      when is_pad_name(pad_name) do
    handle_action({:demand, {pad_name, 1}}, :handle_demand, params, state)
  end

  def handle_action(
        {:demand, {pad_name, size}},
        :handle_demand,
        %{source: src_name} = params,
        state
      )
      when is_pad_name(pad_name) and is_integer(size) do
    handle_action({:demand, {pad_name, {:source, src_name}, size}}, :handle_demand, params, state)
  end

  def handle_action({:demand, {pad_name, {:source, src_name}, size}}, cb, _params, state)
      when is_pad_name(pad_name) and is_pad_name(src_name) and is_integer(size) and size > 0 do
    ActionExec.handle_demand(pad_name, {:source, src_name}, :normal, size, cb, state)
  end

  def handle_action({:demand, {pad_name, :self, size}}, cb, _params, state)
      when is_pad_name(pad_name) and is_integer(size) and size > 0 do
    ActionExec.handle_demand(pad_name, :self, :normal, size, cb, state)
  end

  def handle_action({:demand, {pad_name, :self, {:set_to, size}}}, cb, _params, state)
      when is_pad_name(pad_name) and is_integer(size) and size > 0 do
    ActionExec.handle_demand(pad_name, :self, :set, size, cb, state)
  end

  def handle_action({:demand, {pad_name, _src_name, 0}}, cb, _params, state)
      when is_pad_name(pad_name) do
    debug(
      """
      Ignoring demand of size of 0 requested by callback #{inspect(cb)}
      on pad #{inspect(pad_name)}.
      """,
      state
    )

    {:ok, state}
  end

  def handle_action({:demand, {pad_name, _src_name, size}}, cb, _params, state)
      when is_pad_name(pad_name) and is_integer(size) and size < 0 do
    warn_error(
      """
      Callback #{inspect(cb)} requested demand of invalid size of #{size}
      on pad #{inspect(pad_name)}. Demands' sizes should be positive (0-sized
      demands are ignored).
      """,
      :negative_demand,
      state
    )
  end

  def handle_action({:redemand, src_name}, cb, _params, state)
      when is_pad_name(src_name) and cb not in [:handle_demand, :handle_process] do
    ActionExec.handle_redemand(src_name, state)
  end

  defdelegate handle_action(action, callback, params, state),
    to: Common,
    as: :handle_invalid_action

  defdelegate handle_demand(pad_name, size, state), to: Common

  def handle_redemand(src_name, state) do
    handle_demand(src_name, 0, state)
  end

  def handle_self_demand(pad_name, source, :normal, buf_cnt, state) do
    {:ok, state} = state |> update_sink_self_demand(pad_name, source, &{:ok, &1 + buf_cnt})

    handle_process_pull(pad_name, source, buf_cnt, state)
    |> or_warn_error("""
    Demand of size #{inspect(buf_cnt)} on sink pad #{inspect(pad_name)}
    was raised, and handle_process was called, but an error happened.
    """)
  end

  def handle_self_demand(pad_name, source, :set, buf_cnt, state) do
    {:ok, state} = state |> update_sink_self_demand(pad_name, source, fn _ -> {:ok, buf_cnt} end)

    handle_process_pull(pad_name, source, buf_cnt, state)
    |> or_warn_error("""
    Demand of size #{inspect(buf_cnt)} on sink pad #{inspect(pad_name)}
    was raised, and handle_process was called, but an error happened.
    """)
  end

  def handle_buffer(:push, pad_name, buffers, state) do
    handle_process_push(pad_name, buffers, state)
  end

  def handle_buffer(:pull, pad_name, buffers, state) do
    {{:ok, was_empty?}, state} =
      state
      |> State.get_update_pad_data(:sink, pad_name, :buffer, fn pb ->
        was_empty = pb |> PullBuffer.empty?()

        with {:ok, pb} <- pb |> PullBuffer.store(buffers) do
          {{:ok, was_empty}, pb}
        end
      end)

    if was_empty? do
      with {:ok, state} <- check_and_handle_process(pad_name, state),
           {:ok, state} <- check_and_handle_demands(state),
           do: {:ok, state}
    else
      {:ok, state}
    end
  end

  def handle_process_push(pad_name, buffers, state) do
    context = %Context.Process{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}

    exec_and_handle_callback(:handle_process, [pad_name, buffers, context], state)
    |> or_warn_error("Error while handling process")
  end

  def handle_process_pull(pad_name, source, buf_cnt, state) do
    with {{:ok, out}, state} <-
           state
           |> State.get_update_pad_data(
             :sink,
             pad_name,
             :buffer,
             &(&1 |> PullBuffer.take(buf_cnt))
           ),
         {:out, {_, data}} <-
           (if out == {:empty, []} do
              {:empty_pb, state}
            else
              {:out, out}
            end),
         {:ok, state} <-
           data
           |> Helper.Enum.reduce_with(state, fn v, st ->
             handle_pullbuffer_output(pad_name, source, v, st)
           end) do
      :ok = send_dumb_demand_if_demand_positive_and_pullbuffer_nonempty(pad_name, source, state)
      {:ok, state}
    else
      {:empty_pb, state} -> {:ok, state}
      {:error, reason} -> warn_error("Error while handling process", reason, state)
    end
  end

  defp handle_pullbuffer_output(pad_name, source, {:buffers, buffers, buf_cnt}, state) do
    {:ok, state} = state |> update_sink_self_demand(pad_name, source, &{:ok, &1 - buf_cnt})

    context = %Context.Process{
      caps: state |> State.get_pad_data!(:sink, pad_name, :caps),
      source: source,
      source_caps: state |> State.get_pad_data!(:sink, pad_name, :caps)
    }

    exec_and_handle_callback(:handle_process, [pad_name, buffers, context], state)
  end

  defp handle_pullbuffer_output(pad_name, _src_name, v, state),
    do: Common.handle_pullbuffer_output(pad_name, v, state)

  defp send_dumb_demand_if_demand_positive_and_pullbuffer_nonempty(_pad_name, :self, _state),
    do: :ok

  defp send_dumb_demand_if_demand_positive_and_pullbuffer_nonempty(
         pad_name,
         {:source, src_name},
         state
       ) do
    if state
       |> State.get_pad_data!(:sink, pad_name, :buffer)
       |> PullBuffer.empty?()
       |> Kernel.!() && state |> State.get_pad_data!(:source, src_name, :demand) > 0 do
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

  defdelegate handle_caps(mode, pad_name, caps, state), to: Common

  defp check_and_handle_process(pad_name, state) do
    demand = state |> State.get_pad_data!(:sink, pad_name, :self_demand)

    if demand > 0 do
      handle_process_pull(pad_name, :self, demand, state)
    else
      {:ok, state}
    end
  end

  defp check_and_handle_demands(state) do
    state
    |> State.get_pads_data(:source)
    |> Helper.Enum.reduce_with(state, fn {name, _data}, st ->
      handle_demand(name, 0, st)
    end)
    |> or_warn_error("""
    Membrane tried to execute handle_demand and then handle_process
    for each unsupplied demand, but an error happened.
    """)
  end

  defp update_sink_self_demand(state, pad_name, :self, f),
    do: state |> State.update_pad_data(:sink, pad_name, :self_demand, f)

  defp update_sink_self_demand(state, _pad_name, _src, _f), do: {:ok, state}
end
