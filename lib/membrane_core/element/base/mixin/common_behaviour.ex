defmodule Membrane.Element.Base.Mixin.CommonBehaviour do
  @moduledoc false

  # This module is a mixin with common routines for all elements regarding
  # their callbacks.


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
  @callback handle_init(any) ::
    {:ok, any} |
    {:error, any}


  @doc """
  Callback invoked when element is prepared. It will receive element state.

  Normally this is the place where you will allocate most of the resources
  used by the element. For example, if your element opens a file, this is
  the place to try to actually open it and return error if that has failed.

  Such resources should be released in `handle_stop/1`.

  If it returns `{:ok, new_state}` it just updates element's state to the new
  state.

  If it returns `{:ok, command_list, new_state}` it sends buffers or/and events
  from the given list downstream to the linked elements. That makes sense
  only for elements that have some source pads. If command in the list is
  `{:send, pad_name, [buffers_or_events]}` it will cause sending given buffers
  and/or events downstream to the linked elements via pad of given name.
  Afterwards the element's state will be updated to the new state.

  If it returns `{:error, reason, new_state}` it indicates that something
  went wrong, and element was unable to handle callback. Error along with
  reason will be propagated (TODO) and state will be updated to the new state.
  """
  @callback handle_prepare(any) ::
    {:ok, any} |
    {:ok, Membrane.Element.callback_return_commands_t, any} |
    {:error, any, any}


  @doc """
  Callback invoked when element is supposed to start playing. It will receive
  element state.

  If it returns `{:ok, new_state}` it just updates element's state to the new
  state.

  If it returns `{:ok, command_list, new_state}` it sends buffers or/and events
  from the given list downstream to the linked elements. That makes sense
  only for elements that have some source pads. If command in the list is
  `{:send, pad_name, [buffers_or_events]}` it will cause sending given buffers
  and/or events downstream to the linked elements via pad of given name.
  Afterwards the element's state will be updated to the new state.

  If it returns `{:error, reason, new_state}` it indicates that something
  went wrong, and element was unable to handle callback. Error along with
  reason will be propagated (TODO) and state will be updated to the new state.
  """
  @callback handle_play(any) ::
    {:ok, any} |
    {:ok, Membrane.Element.callback_return_commands_t, any} |
    {:error, any, any}


  @doc """
  Callback invoked when element is supposed to stop playing. It will receive
  element state.

  Normally this is the place where you will release most of the resources
  used by the element. For example, if your element opens a file, this is
  the place to close it.

  If it returns `{:ok, new_state}` it just updates element's state to the new
  state.

  If it returns `{:ok, command_list, new_state}` it sends buffers or/and events
  from the given list downstream to the linked elements. That makes sense
  only for elements that have some source pads. If command in the list is
  `{:send, pad_name, [buffers_or_events]}` it will cause sending given buffers
  and/or events downstream to the linked elements via pad of given name.
  Afterwards the element's state will be updated to the new state.

  If it returns `{:error, reason, new_state}` it indicates that something
  went wrong, and element was unable to handle callback. Error along with
  reason will be propagated (TODO) and state will be updated to the new state.
  """
  @callback handle_stop(any) ::
    {:ok, any} |
    {:ok, Membrane.Element.callback_return_commands_t, any} |
    {:error, any, any}


  @doc """
  Callback invoked when element is receiving message of other kind. It will
  receive the message and element state.

  If it returns `{:ok, new_state}` it just updates element's state to the new
  state.

  If it returns `{:ok, command_list, new_state}` it sends buffers or/and events
  from the given list downstream to the linked elements. That makes sense
  only for elements that have some source pads. If command in the list is
  `{:send, pad_name, [buffers_or_events]}` it will cause sending given buffers
  and/or events downstream to the linked elements via pad of given name.
  Afterwards the element's state will be updated to the new state.

  If it returns `{:error, reason, new_state}` it indicates that something
  went wrong, and element was unable to handle callback. Error along with
  reason will be propagated (TODO) and state will be updated to the new state.
  """
  @callback handle_other(any, any) ::
    {:ok, any} |
    {:ok, Membrane.Element.callback_return_commands_t, any} |
    {:error, any, any}


  @doc """
  Callback invoked when element is shutting down just before process is exiting.
  It will the element state.

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
      def handle_prepare(state), do: {:ok, state}

      @doc false
      def handle_play(state), do: {:ok, state}

      @doc false
      def handle_stop(state), do: {:ok, state}

      @doc false
      def handle_other(_message, state), do: {:ok, state}

      @doc false
      def handle_shutdown(_state), do: :ok


      defoverridable [
        handle_prepare: 1,
        handle_play: 1,
        handle_stop: 1,
        handle_other: 2,
        handle_shutdown: 1,
      ]
    end
  end
end
