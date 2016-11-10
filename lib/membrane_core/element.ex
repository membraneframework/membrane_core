defmodule Membrane.Element do
  @doc """
  This module contains functions that can be applied to all elements.
  """

  use Membrane.Mixins.Log


  @doc """
  Sends synchronous call to the given element requesting it to start playing.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is already playing, returns `:noop`.
  """
  @spec play(pid, timeout) :: :ok | :noop
  def play(server, timeout \\ 5000) do
    debug("Play -> #{inspect(server)}")
    GenServer.call(server, :membrane_play, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to stop playing.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is not playing, returns `:noop`.
  """
  @spec stop(pid, timeout) :: :ok | :noop
  def stop(server, timeout \\ 5000) do
    debug("Stop -> #{inspect(server)}")
    GenServer.call(server, :membrane_stop, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to add given
  element to the list of destinations for buffers that are sent from the
  element.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If destination is already present, returns `:noop`.
  """
  @spec link(pid, pid, timeout) :: :ok | :noop
  def link(server, destination, timeout \\ 5000) do
    debug("Link #{inspect(destination)} -> #{inspect(server)}")
    GenServer.call(server, {:membrane_link, destination}, timeout)
  end


  @doc """
  FIXME remove this, we can use handle_other for the same purpose

  Sends synchronous call to the given element requesting it to send buffer
  to its destinations. It makes sense only for source elements.

  It should not be used in the application, it is added primarily for
  making elements.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.
  """
  @spec send_buffer(pid, %Membrane.Buffer{}, timeout) :: :ok | :noop
  def send_buffer(server, buffer, timeout \\ 5000) do
    debug("Send buffer #{inspect(buffer)} -> #{inspect(server)}")
    GenServer.call(server, {:membrane_send_buffer, buffer}, timeout)
  end
end
