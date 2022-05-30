defmodule Membrane.Core.FilterAggregator.InternalAction do
  @moduledoc false
  # Definitions of actions used internally by Membrane.FilterAggregator

  @type t :: {__MODULE__, atom()} | {__MODULE__, atom(), args :: any()}

  # Playback state change actions
  defmacro stopped_to_prepared() do
    quote do: {unquote(__MODULE__), :stopped_to_prepared}
  end

  defmacro prepared_to_playing() do
    quote do: {unquote(__MODULE__), :prepared_to_playing}
  end

  defmacro playing_to_prepared() do
    quote do: {unquote(__MODULE__), :playing_to_prepared}
  end

  defmacro prepared_to_stopped() do
    quote do: {unquote(__MODULE__), :prepared_to_stopped}
  end

  defmacro start_of_stream(pad) do
    quote do: {unquote(__MODULE__), :start_of_stream, unquote(pad)}
  end

  @doc """
  An action allowing to manipulate the context passed to callbacks
  """
  defmacro merge_context(map) do
    quote do: {unquote(__MODULE__), :merge_context, unquote(map)}
  end

  defguard is_internal_action(action)
           when is_tuple(action) and elem(action, 0) == unquote(__MODULE__)
end
