defmodule Membrane.Element.Action do
  @moduledoc false
  # Module containing action handlers common for elements of all types.

  use Membrane.Mixins.Log
  alias Membrane.Pad
  alias Membrane.Caps
  alias Membrane.Element.State

  def send_buffer(pad_name, %Membrane.Buffer{} = buffer, state) do
    send_buffer(pad_name, [buffer], state)
  end

  @spec send_buffer(Pad.name_t, [Membrane.Buffer.t], State.t) :: :ok
  def send_buffer(pad_name, buffers, state) do
    debug """
      Sending buffers through pad #{inspect(pad_name)}
      Buffers: #{inspect(buffers)}
      """
    with \
      {:ok, %{mode: mode, pid: pid}} <- state |> State.get_pad_data(:source, pad_name),
      {:ok, state} = (case mode do
          :pull -> state |>
            State.update_pad_data(:source, pad_name, :demand, &{:ok, &1 - length buffers})
          :push -> {:ok, state}
        end),
      :ok <- GenServer.call(pid, {:membrane_buffer, buffers})
    do
      {:ok, state}
    else
      {:error, :unknown_pad} ->
        handle_unknown_pad pad_name, :sink, :buffer, state
      {:error, reason} -> warnError """
        Error while sending buffers to pad: #{inspect pad_name}
        Buffers: #{inspect buffers}
        """, reason
    end
  end


  @spec send_caps(Pad.name_t, Caps.t, State.t) :: :ok
  def send_caps(pad_name, caps, state) do
    debug("Caps: pad_name = #{inspect(pad_name)}, caps = #{inspect(caps)}")
    # TODO
    {:ok, state}
  end


  @spec handle_demand(Pad.name_t, Pad.name_t, pos_integer, atom, State.t) :: :ok | {:error, any}
  def handle_demand(pad_name, src_name \\ nil, size, callback, %State{module: module} = state) do
    debug "Sending demand of size #{inspect size} through pad #{inspect(pad_name)}"
    with \
      {:sink, {:ok, %{mode: :pull}}} <-
        {:sink, state |> State.get_pad_data(:sink, pad_name)},
      {:source, {:ok, %{mode: :pull}}} <- {:source, cond do
          src_name != nil -> state |> State.get_pad_data(:source, src_name)
          true -> {:ok, %{mode: :pull}}
        end}
    do
      case callback do
        cb when cb in [:handle_write, :handle_process] ->
          send self(), {:membrane_self_demand, pad_name, src_name, size}
          {:ok, state}
        _ -> module.base_module.handle_self_demand pad_name, src_name, size, state
      end
    else
      {_direction, {:ok, %{mode: :push}}} ->
        handle_invalid_pad_mode pad_name, :pull, :demand, state
      {direction, {:error, :unknown_pad}} ->
        handle_unknown_pad pad_name, direction, :demand, state
    end
  end


  @spec send_event(Pad.name_t, Membrane.Event.t, State.t) :: :ok
  def send_event(pad_name, event, state) do
    debug """
      Sending event through pad #{inspect pad_name}
      Event: #{inspect event}
      """
    with \
      {:ok, %{pid: pid}} <- State.get_pad_data(state, :any, pad_name),
      :ok <- GenServer.call(pid, {:membrane_event, event})
    do {:ok, state}
    else
      {:error, :unknown_pad} ->
        handle_unknown_pad pad_name, :any, :event, state
      {:error, reason} -> warnError """
        Error while sending event to pad: #{inspect pad_name}
        Event: #{inspect event}
        """, reason
    end
  end


  @spec send_message(Membrane.Message.t, State.t) :: :ok
  def send_message(%Membrane.Message{} = message, %State{message_bus: nil} = state) do
    debug "Dropping #{inspect(message)} as message bus is undefined"
    {:ok, state}
  end

  def send_message(%Membrane.Message{} = message, %State{message_bus: message_bus} = state) do
    debug "Sending message #{inspect(message)} (message bus: #{inspect message_bus})"
    send(message_bus, {:membrane_message, message})
    {:ok, state}
  end

  defp handle_invalid_pad_mode(pad_name, expected_mode, action, state) do
    exp_mode_name = Atom.to_string expected_mode
    mode_name = case expected_mode do
      :pull -> "push"
      :push -> "pull"
    end
    action_name = Atom.to_string action
    raise """
    Pad "#{inspect pad_name}" is working in invalid mode: #{inspect mode_name}.

    This is probably a bug in element. It requested an action
    "#{inspect action_name}" on pad "#{inspect pad_name}", but the pad is not
    working in #{inspect exp_mode_name} mode as it is supposed to.

    Element state was:

    #{inspect(state, limit: 100000, pretty: true)}
    """
  end

  defp handle_unknown_pad(pad_name, expected_direction, action, state) do
    direction_name = Atom.to_string expected_direction
    action_name = Atom.to_string action
    raise """
    Pad "#{inspect pad_name}" has not been found.

    This is probably a bug in element. It requested an action
    "#{inspect action_name}" on pad "#{inspect pad_name}", but such pad has not
    been found. #{if expected_direction != :any do
      "It either means that it does not exist, or it is not a
      #{inspect direction_name} pad."
    else "" end}

    Element state was:

    #{inspect(state, limit: 100000, pretty: true)}
    """
  end
end
