defmodule Membrane.Element do
  use Membrane.Mixins.Log

  def play(server) do
    debug("Play -> #{inspect(server)}")
    GenServer.call(server, :membrane_play)
  end


  def stop(server) do
    debug("Stop -> #{inspect(server)}")
    GenServer.call(server, :membrane_stop)
  end


  def link(server, destination) do
    debug("Link #{inspect(destination)} -> #{inspect(server)}")
    GenServer.call(server, {:membrane_link, destination})
  end


  def send_buffer(server, buffer) when is_tuple(buffer) do
    debug("Send buffer #{inspect(buffer)} -> #{inspect(server)}")
    GenServer.call(server, {:membrane_send_buffer, buffer})
  end
end
