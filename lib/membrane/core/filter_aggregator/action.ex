defmodule Membrane.Core.FilterAggregator.InternalAction do
  @moduledoc false
  # Definitions of actions used internally by Membrane.FilterAggregator

  @type t :: {__MODULE__, atom()} | {__MODULE__, atom(), args :: any()}

  defmacro setup() do
    quote do: {unquote(__MODULE__), :setup}
  end

  defmacro playing() do
    quote do: {unquote(__MODULE__), :playing}
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
