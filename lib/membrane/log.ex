defmodule Membrane.Log do
  @moduledoc """
  Mixin for logging using simple functions such as info/1, debug/1 in other
  modules.
  """

  use Membrane.Helper
  alias Membrane.Log.Router

  @doc false
  defmacro __using__(args) do
    passed_tags = args |> Keyword.get(:tags, []) |> Helper.listify()
    previous_tags = Module.get_attribute(__CALLER__.module, :logger_default_tags) || []
    default_tags = (passed_tags ++ previous_tags) |> Enum.dedup()
    Module.put_attribute(__CALLER__.module, :logger_default_tags, default_tags)

    if args |> Keyword.get(:import, true) do
      quote location: :keep do
        import Membrane.Log
      end
    end
  end

  @doc false
  defmacro debug(message, tags \\ []) do
    quote location: :keep do
      Membrane.Log.log(:debug, unquote(message), unquote(tags))
    end
  end

  @doc false
  defmacro info(message, tags \\ []) do
    quote location: :keep do
      Membrane.Log.log(:info, unquote(message), unquote(tags))
    end
  end

  @doc false
  defmacro warn(message, tags \\ []) do
    quote location: :keep do
      Membrane.Log.log(:warn, unquote(message), unquote(tags))
    end
  end

  defmacro warn_error(message, reason, tags \\ []) do
    quote do
      use Membrane.Helper

      Membrane.Log.warn(
        [
          "Encountered an error.\n",
          "Reason: #{inspect(unquote(reason))}\n",
          unquote(message),
          "\n",
          """
          Stacktrace:
          #{Helper.stacktrace()}
          """
        ],
        unquote(tags)
      )

      unquote({:error, reason})
    end
  end

  defmacro or_warn_error(v, message, tags \\ []) do
    quote do
      with {:ok, value} <- unquote(v) do
        {:ok, value}
      else
        {:error, reason} ->
          Membrane.Log.warn_error(unquote(message), reason, unquote(tags))
      end
    end
  end

  @doc false
  defmacro log(level, message, tags) do
    config = Application.get_env(:membrane_core, Membrane.Logger, [])
    router_level = config |> Keyword.get(:level, :debug)
    router_level_val = router_level |> Router.level_to_val()

    quote location: :keep do
      alias Membrane.Log.Router
      use Membrane.Helper
      level_val = unquote(level) |> Router.level_to_val()

      if level_val >= unquote(router_level_val) do
        Router.send_log(
          unquote(level),
          unquote(message),
          Membrane.Time.pretty_now(),
          (unquote(tags) |> Helper.listify()) ++ @logger_default_tags
        )
      end
    end
  end
end
