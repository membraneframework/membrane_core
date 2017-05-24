defmodule Membrane.Pad.Mode.Push do
  @moduledoc false
  # Module contains logic that causes sink pads in the push mode to forward
  # buffers to the parent element's handle_buffer callback so they can consume
  # them.


  use Membrane.Pad.Mode
  use Membrane.Mixins.Log


  # Private API

  @doc false
  # Received from parent element in reaction to the :buffer action.
  # Returns error if pad is not linked, so send cannot succeed.
  def handle_call({:membrane_buffer, _buffer}, _parent, nil, :source, state) do
    debug("Send on non-linked source pad")
    {:reply, {:error, :not_linked}, state}
  end

  # Received from parent element in reaction to the :buffer action.
  # Forwards demand request to the peer but does not wait for reply.
  def handle_call({:membrane_buffer, buffer}, _parent, peer, :source, state) do
    debug("Send on source pad")
    send(peer, {:membrane_buffer, buffer})
    {:reply, :ok, state}
  end

  def handle_other({:membrane_buffer, buffer}, parent, _peer, :sink, state) do
    debug "Send on sink pad"
    send parent, {:membrane_buffer, self(), buffer}
    {:ok, state}
  end
end
