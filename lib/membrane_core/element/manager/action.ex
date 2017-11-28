defmodule Membrane.Element.Manager.Action do
  @moduledoc false
  # Module containing action handlers common for elements of all types.

  use Membrane.Element.Manager.Log
  alias Membrane.{Buffer, Caps, Event, Message, Pad}
  alias Membrane.Element.Manager.State
  use Membrane.Helper

  @spec send_buffer(Pad.name_t, atom, [Buffer.t], State.t) :: :ok | {:error, any}

  def send_buffer(_pad_name, _buffer, callback, %State{playback_state: playback} = state)
  when playback != :playing and callback != :handle_play
  do
    warn_error "Buffers can only be sent when playing or from handle_play callback",
      {:cannot_handle_demand, playback_state: playback, callback: callback}, state
  end

  def send_buffer(pad_name, %Buffer{} = buffer, callback, state) do
    send_buffer pad_name, [buffer], callback, state
  end

  def send_buffer(pad_name, buffers, _callback, state) do
    debug [
      "Sending buffers through pad #{inspect pad_name},
      Buffers: ", Buffer.print(buffers)
      ], state
    with \
      {:ok, %{mode: mode, pid: pid, other_name: other_name, options: options, eos: false}}
        <- state |> State.get_pad_data(:source, pad_name)
    do
      {:ok, state} = (case mode do
          :pull ->
            buf_size = Buffer.Metric.from_unit(options.other_demand_in).buffers_size buffers
            state |> State.update_pad_data(:source, pad_name, :demand, &{:ok, &1 - buf_size})
          :push -> {:ok, state}
        end)
      send pid, {:membrane_buffer, [buffers, other_name]}
      {:ok, state}
    else
      {:ok, %{eos: true}} -> warn_error ["
        Error while sending buffers to pad: #{inspect pad_name}
        Buffers: ", Buffer.print(buffers)
        ], :eos_already_sent, state
      {:error, :unknown_pad} ->
        handle_unknown_pad pad_name, :sink, :buffer, state
      {:error, reason} -> warn_error ["
        Error while sending buffers to pad: #{inspect pad_name}
        Buffers: ", Buffer.print(buffers)
        ], reason, state
    end
  end


  @spec send_caps(Pad.name_t, Caps.t, State.t) :: :ok
  def send_caps(pad_name, caps, state) do
    debug """
      Sending caps through pad #{inspect pad_name}
      Caps: #{inspect caps}
      """, state
    with \
      {:ok, %{pid: pid, other_name: other_name}}
        <- state |> State.get_pad_data(:source, pad_name)
    do
      send pid, {:membrane_caps, [caps, other_name]}
      state |> State.set_pad_data(:source, pad_name, :caps, caps)
    else
      {:error, :unknown_pad} ->
        handle_unknown_pad pad_name, :source, :event, state
      {:error, reason} -> warn_error """
        Error while sending caps to pad: #{inspect pad_name}
        Caps: #{inspect caps}
        """, reason, state
    end
  end


  @spec handle_demand(Pad.name_t, {:source, Pad.name_t} | :self, :normal | :set, pos_integer, atom, State.t) :: :ok | {:error, any}
  def handle_demand(pad_name, source, type, size, callback, state)

  def handle_demand(_pad_name, _source, _type, _size, callback, %State{playback_state: playback} = state)
  when playback != :playing and callback != :handle_play
  do
    warn_error "Demand can only be requested when playing or from handle_play callback",
      {:cannot_handle_demand, playback_state: playback, callback: callback}, state
  end

  def handle_demand(pad_name, source, type, size, callback, %State{module: module} = state) do
    debug "Requesting demand of size #{inspect size} on pad #{inspect pad_name}", state
    with \
      {:sink, {:ok, %{mode: :pull}}} <-
        {:sink, state |> State.get_pad_data(:sink, pad_name)},
      {:source, {:ok, %{mode: :pull}}} <- {:source, case source do
          {:source, src_name} -> state |> State.get_pad_data(:source, src_name)
          :self -> {:ok, %{mode: :pull}}
        end}
    do
      case callback do
        cb when cb in [:handle_write, :handle_process] ->
          send self(), {:membrane_self_demand, [pad_name, source, size]}
          {:ok, state}
        _ -> module.manager_module.handle_self_demand pad_name, source, type, size, state
      end
    else
      {_direction, {:ok, %{mode: :push}}} ->
        handle_invalid_pad_mode pad_name, :pull, :demand, state
      {direction, {:error, :unknown_pad}} ->
        handle_unknown_pad pad_name, direction, :demand, state
    end
  end


  @spec send_event(Pad.name_t, Event.t, State.t) :: :ok
  def send_event(pad_name, event, state) do
    debug """
      Sending event through pad #{inspect pad_name}
      Event: #{inspect event}
      """, state
    with \
      {:ok, %{pid: pid, other_name: other_name}}
        <- State.get_pad_data(state, :any, pad_name),
      {:ok, state} <- handle_event(pad_name, event, state)
    do
      send pid, {:membrane_event, [event, other_name]}
      {:ok, state}
    else
      {:error, :unknown_pad} ->
        handle_unknown_pad pad_name, :any, :event, state
      {:error, reason} -> warn_error """
        Error while sending event to pad: #{inspect pad_name}
        Event: #{inspect event}
        """, reason, state
    end
  end

  defp handle_event(pad_name, %Event{type: :eos}, state) do
    with %{direction: :source, eos: false} <- state |> State.get_pad_data!(:any, pad_name)
    do
      state |> State.set_pad_data(:source, pad_name, :eos, true)
    else
      %{direction: :sink} -> {:error, {:cannot_send_eos_through_sink, pad_name}}
      %{eos: true} -> {:error, {:eos_already_sent, pad_name}}
    end
  end
  defp handle_event(_pad_name, _event, state), do: {:ok, state}


  @spec send_message(Message.t, State.t) :: :ok
  def send_message(%Message{} = message, %State{message_bus: nil} = state) do
    debug "Dropping #{inspect(message)} as message bus is undefined", state
    {:ok, state}
  end

  def send_message(%Message{} = message, %State{message_bus: message_bus, name: name} = state) do
    debug "Sending message #{inspect(message)} (message bus: #{inspect message_bus})", state
    send(message_bus, [:membrane_message, name, message])
    {:ok, state}
  end

  defp handle_invalid_pad_mode(pad_name, expected_mode, action, state) do
    exp_mode_name = Atom.to_string expected_mode
    mode_name = case expected_mode do
      :pull -> "push"
      :push -> "pull"
    end
    action_name = Atom.to_string action
    #TODO: return error instead
    raise """
    Pad "#{inspect pad_name}" is working in invalid mode: #{inspect mode_name}.

    This is probably a bug in Element.Manager. It requested an action
    "#{inspect action_name}" on pad "#{inspect pad_name}", but the pad is not
    working in #{inspect exp_mode_name} mode as it is supposed to.

    element state was:

    #{inspect(state, limit: 100000, pretty: true)}
    """
  end

  defp handle_unknown_pad(pad_name, expected_direction, action, state) do
    direction_name = Atom.to_string expected_direction
    action_name = Atom.to_string action
    #TODO: return error instead
    raise """
    Pad "#{inspect pad_name}" has not been found.

    This is probably a bug in element. It requested an action
    "#{inspect action_name}" on pad "#{inspect pad_name}", but such pad has not
    been found. #{if expected_direction != :any do
      "It either means that it does not exist, or it is not a
      #{inspect direction_name} pad."
    else "" end}

    element state was:

    #{inspect(state, limit: 100000, pretty: true)}
    """
  end
end
