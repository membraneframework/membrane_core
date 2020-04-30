defmodule Membrane.Logger do
  @moduledoc """
  Logging utils.
  """

  # TODO: compile_env should be always used when we require Elixir 1.10
  @config if function_exported?(Application, :compile_env, 3),
            do: Application.compile_env(:membrane_core, :logger, []),
            else: Application.get_env(:membrane_core, :logger, [])

  @prefix_getter (quote do
                    Process.get(:membrane_logger_prefix, "")
                  end)

  defmacrop prefix_prepender(message) do
    quote do
      message = unquote(message)

      if is_function(message, 0) do
        fn ->
          case message.() do
            {content, metadata} -> {[unquote(@prefix_getter), message], metadata}
            content -> [unquote(@prefix_getter), content]
          end
        end
      else
        [unquote(@prefix_getter), message]
      end
    end
  end

  @doc """
  Macro for verbose debug logs that should be silenced by default.

  Debugs done via this macro are displayed only when verbose logging is enabled
  via `Mix.Config`:

      use Mix.Config
      config :membrane_core, :logger, verbose: true

  A `mb_verbose: true` metadata entry is added to each debug.

  Use for debugs that usually pollute the output.
  """
  defmacro debug_verbose(message, metadata \\ []) do
    if Keyword.get(@config, :verbose, false) do
      quote do
        require Logger
        Logger.debug(unquote(prepend_prefix(message)), unquote([mb_verbose: true] ++ metadata))
      end
    else
      # A hack to suppress the 'unused variable' warnings
      quote do
        fn ->
          _ = unquote(message)
          _ = unquote(metadata)
        end

        :ok
      end
    end
  end

  Enum.map([:debug, :info, :warn, :error], fn method ->
    defmacro unquote(method)(message, metadata \\ []) do
      method = unquote(method)

      quote do
        require Logger
        Logger.unquote(method)(unquote(prepend_prefix(message)), unquote(metadata))
      end
    end
  end)

  defmacro log(level, message, metadata \\ []) do
    quote do
      require Logger
      Logger.log(unquote(level), unquote(prepend_prefix(message)), unquote(metadata))
    end
  end

  def bare_log(level, message, metadata \\ []) do
    Logger.bare_log(level, prefix_prepender(message), metadata)
  end

  def get_config() do
    Application.get_env(:membrane_core, :logger, [])
  end

  def get_config(key, default \\ nil) do
    Application.get_env(:membrane_core, :logger, [])
    |> Keyword.get(key, default)
  end

  defp prepend_prefix(message) when is_binary(message) or is_list(message) do
    [@prefix_getter, message]
  end

  defp prepend_prefix({op, _meta, _args} = message) when op in [:<<>>, :<>] do
    [@prefix_getter, message]
  end

  defp prepend_prefix(message) do
    prefix_prepender(message)
  end
end
