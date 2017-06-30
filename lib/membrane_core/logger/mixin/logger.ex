defmodule Membrane.Logger.Behaviour do
  @moduledoc false

  # This module is a mixin with common routines for loger implementations.


  @doc """
  Callback invoked when logger is initialized, right after new process is
  spawned.

  On success it should return `{:ok, initial_logger_state}`.
  """
  @callback handle_init(Membrane.Element.element_options_t) ::
    {:ok, any} |
    {:error, any}




  @doc """
  Callback invoked when new log message is received.

  Callback delivers 5 arguments:
  * log level: atom, one of: :debug, :info, :warn
  * message: basic element or list of basic elements
  * timestamp
  * tags (list of atoms, e.g. module name)
  * logger state


  Basic elements are:
  * atom
  * charlist
  * integer
  * float
  * bitstring


  On success, it returns `{:ok, new_state}`. it will just update logger's state
  to the new state.

  If it returns `{:error, reason, new_state}` it indicates that something
  went wrong, and element was unable to handle log. State will be updated to
  the new state.
  """
  @callback handle_log(atom, any, Membane.Time.native_t, atom, any) :: #FIXME message types
    {:ok, any} |
    {:error, any, any}


  @doc """
  Callback invoked when element is shutting down just before process is exiting.
  It will receive the element state.

  Return value is ignored.

  If shutdown will be invoked without stopping element first, warning will be
  issued and this is considered to be a programmer's mistake. That implicates
  that most of the resources should be normally released in `handle_stop/1`.

  However, you might want to do some additional cleanup when process is exiting,
  and this is the right place to do so.
  """
  @callback handle_shutdown(any) :: any


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Logger.Behaviour

      # Default implementations

      @doc false
      def handle_init(_opts), do: {:ok, %{}}

      @doc false
      def handle_shutdown(_state), do: :ok


      defoverridable [
        handle_init: 1,
        handle_shutdown: 1,
      ]
    end
  end
end
