defmodule Membrane.Mixins.Log do
  @moduledoc """
  Mixin for logging using simple functions such as info/1, debug/1 in other
  modules.
  """

  defmacro __using__(_) do
    quote location: :keep do
      require Logger

      def info(message) do
        Logger.info("[#{List.last(String.split(to_string(__MODULE__), ".", parts: 2))}} #{inspect(self())}] #{message}")
      end


      def warn(message) do
        Logger.warn("[#{List.last(String.split(to_string(__MODULE__), ".", parts: 2))}} #{inspect(self())}] #{message}")
      end


      def debug(message) do
        Logger.debug("[#{List.last(String.split(to_string(__MODULE__), ".", parts: 2))}} #{inspect(self())}] #{message}")
      end
    end
  end
end
