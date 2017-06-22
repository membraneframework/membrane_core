defmodule Membrane.Mixins.Log do
  @moduledoc """
  Mixin for logging using simple functions such as info/1, debug/1 in other
  modules.
  """

  defmacro __using__(_) do
    quote location: :keep do
      require Logger

      @doc false
      defmacro info(message) do
        quote location: :keep do
          Logger.info("[#{System.monotonic_time()} #{List.last(String.split(to_string(__MODULE__), ".", parts: 2))} #{inspect(self())}] #{unquote(message)}")
        end
      end


      @doc false
      defmacro warn(message) do
        quote location: :keep do
          Logger.warn("[#{System.monotonic_time()} #{List.last(String.split(to_string(__MODULE__), ".", parts: 2))} #{inspect(self())}] #{unquote(message)}")
        end
      end

      def warnError(message, reason) do
        warn """
        Encountered an error:
        #{inspect message}
        Reason: #{inspect reason}
        Stacktrace:
        #{Exception.format_stacktrace System.stacktrace}
        """
        {:error, reason}
      end

      def orWarnError({:ok, value}, _msg), do: {:ok, value}
      def orWarnError({:error, reason}, msg), do: warnError(msg, reason)


      @doc false
      defmacro debug(message) do
        quote location: :keep do
          Logger.debug("[#{System.monotonic_time()} #{List.last(String.split(to_string(__MODULE__), ".", parts: 2))} #{inspect(self())}] #{unquote(message)}")
        end
      end
    end
  end
end
