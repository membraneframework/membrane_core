defmodule Membrane.Element.Base.Mixin.SourceCalls do
  @moduledoc false


  defmacro __using__(_) do
    quote location: :keep do
      def handle_call({:membrane_link, destination}, _from, %{link_destinations: link_destinations} = state) do
        case Enum.find(link_destinations, fn(x) -> x == destination end) do
          nil ->
            debug("Handle Link: OK, #{inspect(destination)} added")
            {:reply, :ok, %{state | link_destinations: link_destinations ++ [destination]}}

          _ ->
            warn("Handle Link: Error, #{inspect(destination)} already present")
            {:reply, :noop, state}
        end
      end
    end
  end
end
