defmodule Membrane.Element.Manager.Sink do
  @moduledoc """
  Module responsible for managing sink elements - executing callbacks and
  handling actions.
  """

  use Membrane.Element.Manager.Log
  use Membrane.Element.Manager.Common
  alias Membrane.Element.Manager.{State, ActionExec, Common}
  import Membrane.Element.Pad, only: [is_pad_name: 1]
  alias Membrane.Element.Context
  alias Membrane.PullBuffer
  alias Membrane.Helper
  alias Membrane.Buffer

  # Private API

  def handle_action({:demand, pad_name}, cb, params, state)
      when is_pad_name(pad_name) do
    handle_action({:demand, {pad_name, 1}}, cb, params, state)
  end

  def handle_action({:demand, {pad_name, size}}, cb, _params, state)
      when is_pad_name(pad_name) and is_integer(size) and size > 0 do
    ActionExec.handle_demand(pad_name, :self, :normal, size, cb, state)
  end

  def handle_action({:demand, {pad_name, 0}}, cb, _params, state)
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

  def handle_action({:demand, {pad_name, size}}, cb, _params, state)
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

  def handle_action({:demand, {pad_name, {:set_to, size}}}, cb, _params, state)
      when is_pad_name(pad_name) and is_integer(size) and size >= 0 do
    ActionExec.handle_demand(pad_name, :self, :set, size, cb, state)
  end

  def handle_action({:demand, {pad_name, {:set_to, size}}}, cb, _params, state)
      when is_pad_name(pad_name) and is_integer(size) and size < 0 do
    warn_error(
      """
      Callback #{inspect(cb)} requested to set demand to invalid size of #{size}
      on pad #{inspect(pad_name)}. Demands sizes cannot be negative
      """,
      :negative_demand,
      state
    )
  end

  defdelegate handle_action(action, callback, params, state),
    to: Common,
    as: :handle_invalid_action

  def handle_self_demand(pad_name, :self, type, buf_cnt, state) do
    {:ok, state} =
      case type do
        :normal ->
          state
          |> State.update_pad_data(:sink, pad_name, :self_demand, &{:ok, &1 + buf_cnt})

        :set ->
          state
          |> State.set_pad_data(:sink, pad_name, :self_demand, buf_cnt)
      end

    handle_write(:pull, pad_name, state)
    |> or_warn_error("""
    Demand of size #{inspect(buf_cnt)} on pad #{inspect(pad_name)}
    was raised, and handle_write was called, but an error happened.
    """)
  end

  def handle_buffer(:push, pad_name, buffer, state),
    do: handle_write(:push, pad_name, buffer, state)

  def handle_buffer(:pull, pad_name, buffer, state) do
    {:ok, state} =
      state
      |> State.update_pad_data(:sink, pad_name, :buffer, &(&1 |> PullBuffer.store(buffer)))

    check_and_handle_write(pad_name, state)
    |> or_warn_error(["
        New buffer arrived:", Buffer.print(buffer), "
        and Membrane tried to execute handle_demand and then handle_write
        for each unsupplied demand, but an error happened.
        "])
  end

  def handle_write(:push, pad_name, buffers, state) do
    context = %Context.Write{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}

    exec_and_handle_callback(:handle_write, [pad_name, buffers, context], state)
    |> or_warn_error("Error while handling write")
  end

  def handle_write(:pull, pad_name, state) do
    with {{:ok, out}, state} <-
           state
           |> State.get_update_pad_data(:sink, pad_name, fn %{self_demand: demand, buffer: pb} =
                                                              data ->
             with {{:ok, out}, npb} <- PullBuffer.take(pb, demand) do
               {{:ok, out}, %{data | buffer: npb}}
             end
           end),
         {:out, {_, data}} <-
           (if out == {:empty, []} do
              {:empty_pb, state}
            else
              {:out, out}
            end),
         {:ok, state} <-
           data
           |> Helper.Enum.reduce_with(state, fn v, st ->
             handle_pullbuffer_output(pad_name, v, st)
           end) do
      {:ok, state}
    else
      {:empty_pb, state} -> {:ok, state}
      {:error, reason} -> warn_error("Error while handling write", reason, state)
    end
  end

  defp handle_pullbuffer_output(pad_name, {:buffers, buffers, buf_cnt}, state) do
    {:ok, state} =
      state
      |> State.update_pad_data(:sink, pad_name, :self_demand, &{:ok, &1 - buf_cnt})

    context = %Context.Write{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}
    debug("Executing handle_write with buffers #{inspect(buffers)}", state)
    exec_and_handle_callback(:handle_write, [pad_name, buffers, context], state)
  end

  defp handle_pullbuffer_output(pad_name, v, state),
    do: Common.handle_pullbuffer_output(pad_name, v, state)

  defdelegate handle_caps(mode, pad_name, caps, state), to: Common

  defp check_and_handle_write(pad_name, state) do
    if State.get_pad_data!(state, :sink, pad_name, :self_demand) > 0 do
      handle_write(:pull, pad_name, state)
    else
      {:ok, state}
    end
  end
end
