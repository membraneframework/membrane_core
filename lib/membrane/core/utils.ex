defmodule Membrane.Core.Utils do
  @moduledoc false

  # For some reason GenServer processes sometimes don't print logs about crash, so
  # we add this macro, to ensure that error logs are always printed
  defmacro log_on_error(do: code) do
    error_source =
      case __CALLER__.module do
        Membrane.Core.Element -> "Membrane Element"
        Membrane.Core.Bin -> "Membrane Bin"
        Membrane.Core.Pipeline -> "Membrane Pipeline"
        other -> inspect(other)
      end

    quote do
      try do
        unquote(code)
      rescue
        error ->
          require Membrane.Logger

          Membrane.Logger.error("""
          Error occured in #{unquote(error_source)}:
          #{Exception.format(:error, error, __STACKTRACE__)}
          """)

          reraise error, __STACKTRACE__
      end
    end
  end
end
