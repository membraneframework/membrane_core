defmodule Membrane.Element.Base.Mixin.CommonBehaviour do
  @moduledoc """
  Behaviour common for elements of all types.
  """


  @doc """
  Callback invoked when element is initialized, right after new process is
  spawned. It will receive options passed to `Membrane.Element.start_link/3`
  or `Membrane.Element.start/3`.

  On success it should return `{:ok, initial_element_state}`. Then given state
  becomes first element's state.

  On failure it should return `{:error, reason}`.

  Returning error will terminate the process without calling `handle_shutdown/1`
  callback.
  """
  @callback handle_init(Membrane.Element.element_options_t) ::
    {:ok, any} |
    {:error, any}


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
      @behaviour Membrane.Element.Base.Mixin.CommonBehaviour

      # Default implementations

      @doc false
      def handle_init(_options), do: {:ok, %{}}

      @doc false
      def handle_shutdown(_state), do: :ok


      defoverridable [
        handle_init: 1,
        handle_shutdown: 1,
      ]
    end
  end
end
