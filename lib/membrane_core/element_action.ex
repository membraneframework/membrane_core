defmodule Membrane.Element.Action do
  @moduledoc false
  # Module containing action handlers common for elements of all types.

  use Membrane.Mixins.Log
  alias Membrane.Pad
  alias Membrane.Caps
  alias Membrane.Element
  alias Membrane.Element.State

  def handle_buffer(pad_name, %Membrane.Buffer{} = buffer, state) do
    handle_buffer(pad_name, [buffer], state)
  end

  @spec handle_buffer(Pad.name_t, [Membrane.Buffer.t], State.t) :: :ok
  def handle_buffer(pad_name, buffers, state) do
    debug("Buffer: pad_name = #{inspect(pad_name)}, buffers = #{inspect(buffers)}")
    with \
      {:ok, {_availability, _direction, mode, pid}} <- State.get_pad_by_name(state, :source, pad_name),
      :ok <- GenServer.call(pid, {:membrane_buffer, buffers})
    do
      state = cond do
        mode == :pull -> State.update_pad_data! state, :source, pad_name, :demand, & &1 - length buffers
        true -> state
      end
      {:ok, state}
    else
      {:error, :unknown_pad} ->
        handle_unknown_pad pad_name, :sink, :buffer, state
      {:error, reason} -> {:error, reason}
    end
  end


  @spec handle_caps(Pad.name_t, Caps.t, State.t) :: :ok
  def handle_caps(pad_name, caps, state) do
    debug("Caps: pad_name = #{inspect(pad_name)}, caps = #{inspect(caps)}")
    # TODO
    {:ok, state}
  end


  @spec handle_demand(Pad.name_t, pos_integer, atom, State.t) :: :ok | {:error, any}
  def handle_demand(pad_name, size, callback, state) do
    debug("Demand: pad_name = #{inspect(pad_name)}")
    with \
      {:ok, {_availability, _direction, mode, _pid}} <- State.get_pad_by_name(state, :sink, pad_name),
      :pull <- mode
    do
      case callback do
        cb when cb in [:handle_write, :handle_process] ->
          send self(), {:membrane_self_demand, pad_name, size, callback}
          {:ok, state}
        _ -> Element.handle_self_demand pad_name, size, callback, state
      end
    else
      :push ->
        handle_invalid_pad_mode pad_name, :pull, :demand, state
      {:error, :unknown_pad} ->
        handle_unknown_pad pad_name, :sink, :demand, state
    end
  end


  @spec handle_event(Pad.name_t, Membrane.Event.t, State.t) :: :ok
  def handle_event(pad_name, event, state) do
    debug("Event: pad_name = #{inspect(pad_name)}, event = #{inspect(event)}")
    {:ok, state}

    # TODO add pad handling code
    # case State.get_pad_by_name(state, :source, pad_name) do
    #   {:ok, {_availability, _direction, _mode, pid}} ->
    #     case GenServer.call(pid, {:membrane_event, event}) do
    #       :ok ->
    #         {:ok, state}
    #
    #       {:error, reason} ->
    #         {:error, reason}
    #     end
    #
    #   {:error, :unknown_pad} ->
    #     case State.get_pad_by_name(state, :sink, pad_name) do
    #       {:ok, {_availability, _direction, _mode, pid}} ->
    #         case GenServer.call(pid, {:membrane_event, event}) do
    #           :ok ->
    #             {:ok, state}
    #
    #           {:error, reason} ->
    #             {:error, reason}
    #         end
    #
    #       {:error, :unknown_pad} ->
    #         raise """
    #         Element seems to be buggy.
    #
    #         It has sent the :event action specyfying #{inspect(pad_name)} as
    #         pad name that is supposed to handle demand.
    #
    #         Such pad was not found.
    #
    #         Element state was:
    #
    #         #{inspect(state, limit: 100000, pretty: true)}
    #         """
    #     end
    # end
  end


  @spec handle_message(Membrane.Message.t, State.t) :: :ok
  def handle_message(%Membrane.Message{} = message, %State{message_bus: nil} = state) do
    debug("Message: message_bus = nil, message = #{inspect(message)}")
    {:ok, state}
  end

  def handle_message(%Membrane.Message{} = message, %State{message_bus: message_bus} = state) do
    debug("Message: message_bus = #{inspect(message_bus)}, message = #{inspect(message)}")
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
    been found. It either means that it does not exist,
    or it is not a #{inspect direction_name} pad.

    Element state was:

    #{inspect(state, limit: 100000, pretty: true)}
    """
  end
end
