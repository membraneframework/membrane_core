defmodule Membrane.Buffer.Metadata do
  @moduledoc """
  Data structure containing additional informations about buffers.
  Basically, it is a simple wrapper around Map
  """

  @type t :: map
  @type key :: any
  @type value :: any

  @doc """
  Puts the given `value` under 'key'
  If the `key` already exists in `meta`, old `value` will be updated
  """
  @spec put(t, key, value) :: t
  def put(meta, key, value) do
    meta |> Map.put(key, value)
  end

  @doc """
  Deletes the entry for a specific `key`.
  If the `key` does not exist, returns `meta` unchanged.
  """
  @spec delete(t, key) :: t
  def delete(meta, key) do
    meta |> Map.delete(key)
  end

  @doc """
  Returns true if the given key exists in the `meta`
  """
  @spec has_key?(t, key) :: boolean
  def has_key?(meta, key) do
    meta |> Map.has_key?(key)
  end

  @doc """
  Updates the entry for a specific `key`.
  If the `key` does not exist, returns `meta` unchanged.
  """
  @spec update(t, key, value) :: t
  def update(meta, key, value) do
    case has_key?(meta, key) do
      true ->
        meta |> put(key, value)

      false ->
        meta
    end
  end

  @doc """
  Returns empty Metadata
  """
  @spec new :: t
  def new do
    Map.new()
  end
end
