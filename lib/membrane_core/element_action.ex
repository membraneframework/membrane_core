defmodule Membrane.Element.Action do
  @moduledoc false
  # Module containing action handlers common for elements of all types.

  use Membrane.Mixins.Log
  alias Membrane.Pad
  alias Membrane.Caps
  alias Membrane.Element
  alias Membrane.Element.State

  @spec handle_buffer(Pad.name_t, Membrane.Buffer.t, State.t) :: :ok
  def handle_buffer(pad_name, buffer, state) do
    debug("Buffer: pad_name = #{inspect(pad_name)}, buffer = #{inspect(buffer)}")
    case State.get_pad_by_name(state, :source, pad_name) do
      {:ok, {_availability, _direction, _mode, pid}} ->
        case GenServer.call(pid, {:membrane_buffer, buffer}) do
          :ok ->
            {:ok, state}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :unknown_pad} ->
        raise """
        Element seems to be buggy.

        It has sent the :buffer action specyfying #{inspect(pad_name)} as
        pad name that is supposed to handle demand.

        Such pad was not found. It either means that it does not exist or
        it is not a source pad.

        Element state was:

        #{inspect(state, limit: 100000, pretty: true)}
        """
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
    case State.get_pad_by_name(state, :sink, pad_name) do
      {:ok, {_availability, _direction, mode, _pid}} ->
        case mode do
          :pull ->
            case callback do
              cb when cb in [:handle_write, :handle_process] ->
                send self(), {:membrane_self_demand, pad_name, size, callback}
                {:ok, state}
              _ -> Element.handle_self_demand pad_name, size, callback, state
            end
          :push ->
            raise """
            Element seems to be buggy.

            It has sent the :demand action specyfying #{inspect(pad_name)} as
            pad name that is supposed to handle demand.

            Such pad was found but it is defined as working in the push mode.
            Demand can be sent upstream only from pads working in the pull mode.

            Element state was:

            #{inspect(state, limit: 100000, pretty: true)}
            """
        end

      {:error, :unknown_pad} ->
        raise """
        Element seems to be buggy.

        It has sent the :demand action specyfying #{inspect(pad_name)} as
        pad name that is supposed to handle demand.

        Such pad was not found. It either means that it does not exist or
        it is not a sink pad.

        Element state was:

        #{inspect(state, limit: 100000, pretty: true)}
        """
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
end
