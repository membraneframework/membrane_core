defmodule Membrane.Element.Base.Mixin.CommonBehaviour do
  @moduledoc """
  This module is a mixin with common routines for all elements regarding
  their callbacks.
  """


  @doc """
  Callback invoked when element is initialized. It will receive options
  passed to start_link.

  On success it should return `{:ok, element_state}`.

  On failure it should return `{:error, reason}`.

  Returning error will terminate the process.
  """
  @callback handle_init(any) ::
    {:ok, any} |
    {:error, any}


  @doc """
  Callback invoked when element is prepared. It will receive element state.

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
  Callback invoked when element is receiving message of other kind.
  It will receive the message and element state.

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


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Element.Base.Mixin.CommonBehaviour

      # Default implementations

      def handle_prepare(state), do: {:ok, state}


      def handle_play(state), do: {:ok, state}


      def handle_stop(state), do: {:ok, state}


      def handle_other(_message, state), do: {:ok, state}


      defoverridable [
        handle_prepare: 1,
        handle_play: 1,
        handle_stop: 1,
        handle_other: 2,
      ]
    end
  end
end
