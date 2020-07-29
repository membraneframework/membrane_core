defmodule Membrane.Helper.PathLocator do
  @moduledoc """
  Helper module for tracing element's path inside of a pipeline.
  Path is a list consisted of following pipeline/bin/element names down the assembled pipeline.
  Information is being stored in a process dictionary and can be set/appended to.
  """

  @type path_t :: list(String.t())

  @key :membrane_path

  @doc """
  Appends given name to the current path.

  If path has not been previously set then creates new one with given name.
  """
  @spec append_path(String.t()) :: :ok
  def append_path(name) do
    path = Process.get(@key, [])
    Process.put(@key, path ++ [name])
    :ok
  end

  @doc """
  Sets current path.

  If path had already existed then replaces it.
  """
  @spec set_path(path_t) :: :ok
  def set_path(path) do
    Process.put(@key, path)
    :ok
  end

  @doc """
  Convenient combination of `set_path/1` and `append_path/1`.
  """
  @spec set_and_append_path(path_t(), String.t()) :: :ok
  def set_and_append_path(path, name) do
    :ok = set_path(path)
    append_path(name)
  end

  @doc """
  Returns formatted string of given path's names joined with separator.
  """
  @spec format_path(path_t(), String.t()) :: String.t()
  def format_path(path, separator \\ "/") do
    path |> Enum.join(separator)
  end

  @doc """
  Works the same as `format_path/2` but uses currently stored path
  """
  @spec get_formatted_path(String.t()) :: String.t()
  def get_formatted_path(separator \\ "/") do
    Process.get(@key, []) |> format_path(separator)
  end

  @doc """
  Returns currently stored path.

  If path has not been set, empty list is returned.
  """
  @spec get_path() :: list(String.t())
  def get_path(), do: Process.get(@key, [])
end
