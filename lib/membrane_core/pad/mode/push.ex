defmodule Membrane.Pad.Mode.Push do
  @moduledoc false
  # Module contains logic that causes sink pads in the push mode to forward
  # buffers to the parent element's handle_buffer callback so they can consume
  # them.


  use Membrane.Pad.Mode
  use Membrane.Mixins.Log


  # Private API

  @doc false
  def handle_call(_message, _parent, nil, _name, _direction, state) do
    warn "Call on non-linked pad"
    {:reply, {:error, :not_linked}, state}
  end
  def handle_call(message, _parent, peer, _name, _direction, state) do
    send peer, message
    {:reply, :ok, state}
  end

  @doc false
  def handle_other(message, parent, _peer, _name, _direction, state) do
    GenServer.call parent, {message, self()}
    {:ok, state}
  end


  # @doc false
  # # Received from parent element in reaction to the :buffer action.
  # # Returns error if pad is not linked, so send cannot succeed.
  # def handle_call({:membrane_buffer, _buffer}, _parent, nil, _name, :source, state) do
  #   warn "Send on non-linked source pad"
  #   {:reply, {:error, :not_linked}, state}
  # end
  #
  # # Received from parent element in reaction to the :buffer action.
  # # Forwards demand request to the peer but does not wait for reply.
  # def handle_call({:membrane_buffer, buffer}, _parent, peer, _name, :source, state) do
  #   # debug("Send on source pad")
  #   send(peer, {:membrane_buffer, buffer})
  #   {:reply, :ok, state}
  # end
  #
  # def handle_other({:membrane_buffer, buffer}, parent, _peer, _name, :sink, state) do
  #   # debug "Send on sink pad"
  #   send parent, {:membrane_buffer, self(), :push, buffer}
  #   {:ok, state}
  # end
end
