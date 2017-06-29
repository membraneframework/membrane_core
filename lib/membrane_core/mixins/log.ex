defmodule Membrane.Mixins.Log do
  @moduledoc """
  Mixin for logging using simple functions such as info/1, debug/1 in other
  modules.
  """

  defmacro __using__(_) do
    quote location: :keep do
      alias Membrane.Logger.Supervisor

      defmacro info(message) do
        quote location: :keep do
          Supervisor.log(:info,  unquote(message), Membrane.Time.native_monotonic_time, :tag)
        end
      end


      defmacro warn(message) do
        quote location: :keep do
          # Logger.warn("[#{System.monotonic_time()} #{List.last(String.split(to_string(__MODULE__), ".", parts: 2))} #{inspect(self())}] #{unquote(message)}")
        end
      end


      defmacro debug(message) do
        quote location: :keep do
          # Logger.debug("[#{System.monotonic_time()} #{List.last(String.split(to_string(__MODULE__), ".", parts: 2))} #{inspect(self())}] #{unquote(message)}")
        end
      end
    end
  end
end
