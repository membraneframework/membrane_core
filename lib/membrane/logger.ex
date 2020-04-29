defmodule Membrane.Logger do
  @moduledoc """
  Logging utils.
  """

  # TODO: compile_env should be always used when we require Elixir 1.10
  @get_env_fun if function_exported?(Application, :compile_env, 3),
                 do: :compile_env,
                 else: :get_env

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
    if Keyword.get(get_config(), :verbose, false) do
      quote do
        Logger.debug(unquote(message), unquote([mb_verbose: true] ++ metadata))
      end
    else
      # A hack to suppress the 'unused variable' warnings
      quote do
        fn ->
          _ = unquote(message)
          _ = unquote(metadata)
        end
      end
    end
  end

  defp get_config() do
    apply(Application, @get_env_fun, [:membrane_core, :logger, []])
  end
end
