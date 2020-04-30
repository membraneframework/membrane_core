defmodule Membrane.Log do
  @moduledoc deprecated: "Use Elixir `Logger` or `Membrane.Logger` instead"
  @moduledoc """
  Mixin for logging using simple functions such as info/1, debug/1 in other
  modules.
  """

  use Bunch
  alias Membrane.Log.Router

  @type level_t :: :debug | :info | :warn

  defmacro __using__(args) do
    passed_tags = args |> Keyword.get(:tags, []) |> Bunch.listify()
    previous_tags = Module.get_attribute(__CALLER__.module, :logger_default_tags) || []
    default_tags = (passed_tags ++ previous_tags) |> Enum.uniq()
    Module.put_attribute(__CALLER__.module, :logger_default_tags, default_tags)

    if args |> Keyword.get(:import, true) do
      quote location: :keep do
        import Membrane.Log
      end
    end
  end

  defmacro debug(message, tags \\ []) do
    do_log(:debug, message, tags, __CALLER__)
  end

  defmacro info(message, tags \\ []) do
    do_log(:info, message, tags, __CALLER__)
  end

  defmacro warn(message, tags \\ []) do
    do_log(:warn, message, tags, __CALLER__)
  end

  defmacro warn_error(message, reason, tags \\ []) do
    message =
      quote do
        require Bunch.Code

        [
          "Encountered an error.\n",
          "Reason: #{inspect(unquote(reason))}\n",
          unquote(message),
          "\n",
          """
          Stacktrace:
          #{Bunch.Code.stacktrace()}
          """
        ]
      end

    quote location: :keep do
      unquote(do_log(:warn, message, tags, __CALLER__))
      unquote({:error, reason})
    end
  end

  defmacro or_warn_error(v, message, tags \\ []) do
    quote location: :keep do
      with {:ok, value} <- unquote(v) do
        {:ok, value}
      else
        {:error, reason} ->
          Membrane.Log.warn_error(unquote(message), reason, unquote(tags))
      end
    end
  end

  defmacro log(level, message, tags \\ []) do
    do_log(level, message, tags, __CALLER__)
  end

  defp do_log(level, message, tags, caller) do
    config = Application.get_env(:membrane_core, Membrane.Logger, [])
    router_level = config |> Keyword.get(:level, :debug)
    router_level_val = router_level |> Router.level_to_val()

    default_tags =
      if caller.module do
        quote_expr(@logger_default_tags)
      else
        quote_expr([])
      end

    send_code =
      quote do
        require Membrane.Logger

        Membrane.Logger.log(unquote(level), unquote(message),
          membrane_tags: inspect(Bunch.listify(unquote(tags)) ++ unquote(default_tags))
        )
      end

    cond do
      not is_atom(level) ->
        quote location: :keep do
          if Router.level_to_val(level) >= unquote(router_level_val) do
            unquote(send_code)
          end

          :ok
        end

      level |> Router.level_to_val() >= router_level_val ->
        quote location: :keep do
          unquote(send_code)
          :ok
        end

      true ->
        # A hack to avoid 'unused variable' warnings when pruning log message creation
        quote location: :keep do
          if false do
            _ = unquote(message)
            _ = unquote(tags)
          end

          :ok
        end
    end
  end
end
