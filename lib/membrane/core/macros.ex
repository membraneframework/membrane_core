defmodule Membrane.Core.Macros do
  @moduledoc false

  defmacro log_on_error(do: code) do
    quote do
      try do
        unquote(code)
      rescue
        e ->
          require Membrane.Logger

          Membrane.Logger.error("""
          Error occured in Membrane Component:
          #{inspect(e, pretty: true, limit: :infinity)}
          #{Exception.format_stacktrace(__STACKTRACE__)}
          """)

          reraise e, __STACKTRACE__
      end
    end
  end
end
