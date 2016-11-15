defmodule Membrane.Element.Base.Mixin.CommonBehaviour do
  @moduledoc """
  This module is a mixin with common routines for all elements regarding
  their callbacks.
  """


  @doc """
  Callback invoked when element is initialized. It will receive options
  passed to start_link.

  On success it should return `{:ok, element_state}`.
  """
  @callback handle_init(any) ::
    {:ok, any} |
    {:error, any}


  @doc """
  Callback invoked when element is prepared. It will receive element state.
  """
  @callback handle_prepare(any) ::
    {:ok, any} |
    {:error, any}


  @doc """
  Callback invoked when element is supposed to start playing. It will receive
  element state.
  """
  @callback handle_play(any) ::
    {:ok, any} |
    {:error, any}


  @doc """
  Callback invoked when element is supposed to stop playing. It will receive
  element state.
  """
  @callback handle_stop(any) ::
    {:ok, any} |
    {:error, any}


  @doc """
  Callback invoked when element is receiving message of other kind.
  It will receive the message and element state.
  """
  @callback handle_other(any, any) ::
    {:ok, any} |
    {:send, [%Membrane.Buffer{}], any} |
    {:error, any, any}


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Element.Base.Mixin.CommonBehaviour

      # Default implementations

      def handle_prepare(_options), do: {:ok, %{}}


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
