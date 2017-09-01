defmodule Membrane.Mixins.Log do
  @moduledoc """
  Mixin for logging using simple functions such as info/1, debug/1 in other
  modules.
  """

  use Membrane.Helper

  @doc false
  defmacro __using__(args) do
    default_tags = args |> Keyword.get(:tags, []) |> Helper.listify
    quote location: :keep do
      alias Membrane.Log.Router

      @doc false
      defmacrop log(level, message, tags) do
        config = Application.get_env(:membrane_core, Membrane.Logger, [])
        router_level = config |> Keyword.get(:level, :debug)
        router_level_val = router_level |> Router.level_to_val

        quote location: :keep do
          level_val = unquote(level) |> Router.level_to_val
          if level_val >= unquote(router_level_val) do
            Router.send_log(unquote(level),  unquote(message), Membrane.Time.monotonic_time, unquote(tags))
          end
        end
      end

      @doc false
      defmacrop info(message, tags \\ []) do
        default_tags = unquote default_tags
        quote location: :keep do
          log(:info, unquote(message), unquote(tags) ++ unquote(default_tags))
        end
      end

      @doc false
      defmacrop warn(message, tags \\ []) do
        default_tags = unquote default_tags
        quote location: :keep do
          log(:warn, unquote(message), unquote(tags) ++ unquote(default_tags))
        end
      end

      defmacrop warn_error(message, reason) do
        quote do
          use Membrane.Helper
          warn """
          Encountered an error:
          #{unquote message}
          Reason: #{inspect unquote reason}
          Stacktrace:
          #{Helper.stacktrace}
          """
          unquote {:error, reason}
        end
      end

      defmacrop or_warn_error(v, message) do
        quote do
          with {:ok, value} <- unquote v
          do {:ok, value}
          else {:error, reason} -> warn_error(unquote(message), reason)
          end
        end
      end
      # defp or_warn_error({:ok, value}, _msg), do: {:ok, value}
      # defp or_warn_error({:error, reason}, msg), do: warn_error(msg, reason)


      @doc false
      defmacrop debug(message, tags \\ []) do
        default_tags = unquote default_tags
        quote location: :keep do
          log(:debug, unquote(message), unquote(tags) ++ unquote(default_tags))
        end
      end
    end
  end
end
