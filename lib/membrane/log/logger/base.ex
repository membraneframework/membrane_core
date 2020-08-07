defmodule Membrane.Log.Logger.Base do
  @moduledoc deprecated: "Use Elixir `Logger` instead"
  @moduledoc """
    This is a base module used by all logger implementations.
  """

  @doc """
  Callback invoked when logger is initialized, right after new process is
  spawned.

  On success it should return `{:ok, initial_logger_state}`.
  """
  @callback handle_init(Membrane.Log.Logger.logger_options_t()) ::
              {:ok, any}
              | {:error, any}

  @doc """
  Callback invoked when new log message is received.

  Callback delivers 5 arguments:
  * atom containing log level
  * message - in IO list format
  * time
  * tags (list of atoms, e.g. module name)
  * internal logger state


  On success, it returns `{:ok, new_state}`. it will just update logger's state
  to the new state.

  If it returns `{:error, reason, new_state}` it indicates that something
  went wrong, and logger was unable to handle log. State will be updated to
  the new state.
  """
  @callback handle_log(
              Membrane.Log.Logger.msg_level_t(),
              Membrane.Log.Logger.message_t(),
              String.t(),
              list(Membrane.Log.Logger.tag_t()),
              any
            ) ::
              {:ok, any}
              | {:error, any, any}

  @doc """
  Callback invoked when logger is shutting down just before process is exiting.
  It will receive the logger state.

  Return value is ignored.
  """
  @callback handle_shutdown(any) :: any

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Log.Logger.Base

      # Default implementations

      @impl true
      def handle_init(_opts), do: {:ok, %{}}

      @impl true
      def handle_shutdown(_state), do: :ok

      defoverridable handle_init: 1,
                     handle_shutdown: 1
    end
  end
end
