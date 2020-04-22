defmodule Membrane.Logger do
  @moduledoc """
  Logging utils.
  """

  @get_env_fun if function_exported?(Application, :compile_env, 3),
                 do: :compile_env,
                 else: :get_env

  @doc """
  Macro for verbose debug logs that should be silenced by default.

  Debugs done via this macro are displayed only when verbosity is set to `:verbose`
  via `Mix.Config`:

      use Mix.Config
      config :membrane_core, :logger, verbosity: :verbose

  while the default verbosity is `:normal`.

  A `mb_verbosity: :verbose` metadata entry is added to each debug.

  Use for debugs that usually pollute the output.
  """
  defmacro debug_verbose(message, metadata \\ []) do
    case Keyword.get(get_config(), :verbosity, :normal) do
      :verbose ->
        quote do
          Logger.debug(unquote(message), unquote([mb_verbosity: :verbose] ++ metadata))
        end

      :normal ->
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
