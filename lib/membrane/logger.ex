defmodule Membrane.Logger do
  @moduledoc """
  Wrapper around the Elixir logger. Adds Membrane prefixes and handles verbose logging.

  ## Prefixes

  By default, this wrapper prepends each log with a prefix containing the context
  of the log, such as element name. This can be turned off via configuration:

      use Mix.Config
      config :membrane_core, :logger, prefix: false

  Regardless of the config, the prefix is passed to `Logger` metadata under `:mb` key.
  Prefixes are passed via process dictionary, so they have process-wide scope,
  but it can be extended with `get_prefix/0` and `set_prefix/1`.

  ## Verbose logging

  For verbose debug logs that should be silenced by default, use `debug_verbose/2`
  macro. Verbose logs are purged in the compile time, unless turned on via configuration:

      use Mix.Config
      config :membrane_core, :logger, verbose: true

  Verbose debugs should be used for logs that are USUALLY USEFUL for debugging,
  but printed so often that they make the output illegible. For example, it may
  be a good idea to debug_verbose from within `c:Membrane.Filter.handle_process/4`
  or `c:Membrane.Element.WithOutputPads.handle_demand/5` callbacks.
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
  Macro for verbose debug logs, that are silenced by default.

  For details, see the 'verbose logging' section of the moduledoc.
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
    @doc """
    Wrapper around `Logger.#{method}/2` that adds Membrane prefix.

    For details, see the 'prefixes' section of the moduledoc.
    """
    defmacro unquote(method)(message, metadata \\ []) do
      method = unquote(method)

      quote do
        require Logger
        Logger.unquote(method)(unquote(prepend_prefix(message)), unquote(metadata))
      end
    end
  end)

  @doc """
  Wrapper around `Logger.log/3` that adds Membrane prefix.

  For details, see the 'prefixes' section of the moduledoc.
  """
  defmacro log(level, message, metadata \\ []) do
    quote do
      require Logger
      Logger.log(unquote(level), unquote(prepend_prefix(message)), unquote(metadata))
    end
  end

  @doc """
  Wrapper around `Logger.bare_log/3` that adds Membrane prefix.

  For details, see the 'prefixes' section of the moduledoc.
  """
  @spec bare_log(Logger.level(), Logger.message(), Logger.metadata()) :: :ok
  def bare_log(level, message, metadata \\ []) do
    Logger.bare_log(level, prefix_prepender(message), metadata)
  end

  @doc """
  Returns the logger prefix.

  Returns an empty string if no prefix is set.
  """
  @spec get_prefix() :: String.t()
  def get_prefix() do
    Process.get(:membrane_logger_prefix, "")
  end

  @doc """
  Sets the logger prefix. Avoid using in Membrane-managed processes.

  This function is intended to enable setting prefix obtained in a Membrane-managed
  process via `get_prefix/1`. If some custom data needs to be prepended to logs,
  please use `Logger.metadata/2`.

  Prefixes in Membrane-managed processes are set automatically and using this
  function there would overwrite them, which is usually unintended.
  """
  @spec set_prefix(prefix :: String.t()) :: :ok
  def set_prefix(prefix) do
    Logger.metadata(mb: prefix)

    if Membrane.Logger.get_config(:prefix, true) do
      Process.put(:membrane_logger_prefix, "[" <> prefix <> "] ")
    end

    :ok
  end

  @doc """
  Returns the Membrane logger config.
  """
  @spec get_config() :: Keyword.t()
  def get_config() do
    Application.get_env(:membrane_core, :logger, [])
  end

  @doc """
  Returns value at given key in the Membrane logger config.
  """
  @spec get_config(key, value) :: value when key: atom, value: any
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
