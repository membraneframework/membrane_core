defmodule Membrane.Helper.LocationPath do
  @moduledoc """
  Helper module for registering following element/bin names inside of created pipeline.
  Registered path will be used by logger and metric events.
  """

  @type path_t :: list(String.t)

  @key :membrane_path

  @doc """
  Appends given name to currently stored path.
  If current path is empty, creates a new one with single name.
  """
  @spec append_current_path(String.t) :: :ok
  def append_current_path(name) do
    path = Process.get(@key, [])
    Process.put(@key, path ++ [name])
    :ok
  end

  @doc """
  Creates or replaces current path.
  """
  @spec set_current_path(path_t) :: :ok
  def set_current_path(path) do
    Process.put(@key, path)
    :ok
  end

  @doc """
  Returns formatted string of current path in form of '<first name>/<second name>/.../<last name>'
  """
  @spec get_formatted_path() :: String.t
  def get_formatted_path() do
    Process.get(@key, []) |> Enum.join("/")
  end

  @doc """
  Returns current path as list of names from deepest to newest
  """
  @spec get_current_path() :: list(String.t)
  def get_current_path(), do: Process.get(@key, [])
end
