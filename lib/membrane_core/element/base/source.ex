defmodule Membrane.Element.Base.Source do
  @moduledoc """
  This module should be used by all elements that are sources.
  """


  defmacro __using__(_) do
    quote do
      use Membrane.Element.Base.Mixin.Process


      def link(server, destination) do
        debug("Link #{inspect(destination)} -> #{inspect(server)}")
        GenServer.call(server, {:membrane_link, destination})
      end


      def send_buffer(server, caps, data) do
        debug("Send buffer #{inspect(data)} -> #{inspect(server)}")
        GenServer.call(server, {:membrane_send_buffer, caps, data})
      end


      def handle_call({:membrane_link, destination}, _from, %{link_destinations: link_destinations} = state) do
        cond Enum.find(link_destinations, fn(x) -> x == destination end) do
          nil ->
            debug("Handle Link: OK, #{inspect(destination)} added")
            {:reply, :ok, %{state | link_destinations: link_destinations ++ [destination]}}

          _ ->
            debug("Handle Link: Error, #{inspect(destination)} already present")
            {:reply, :noop, state}
        end
      end


      def handle_call({:membrane_send_buffer, caps, data}, _from, %{link_destinations: link_destinations} = state) do
        :ok = send_buffer_loop(caps, data, link_destinations)
        {:reply, :ok, state}
      end


      defp send_buffer_loop(_caps, _data, []) do
        :ok
      end


      defp send_buffer_loop(caps, data, [head|tail]) do
        send(head, {:membrane_buffer, {caps, data}})
        send_buffer_loop(caps, data, tail)
      end
    end
  end
end
