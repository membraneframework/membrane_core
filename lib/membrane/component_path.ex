defmodule Membrane.ComponentPath do
  @moduledoc """
  Traces element's path inside a pipeline.
  Path is a list consisted of following pipeline/bin/element names down the assembled pipeline.
  Information is being stored in a process dictionary and can be set/appended to.
  """

  @type path_t :: list(String.t())

  @key :membrane_path

  @doc """
  Appends given name to the current path.

  If path has not been previously set then creates new one with given name.
  """
  @spec append(String.t()) :: :ok
  def append(name) do
    path = Process.get(@key, [])
    Process.put(@key, path ++ [name])
    :ok
  end

  @doc """
  Sets current path.

  If path had already existed then replaces it.
  """
  @spec set(path_t) :: :ok
  def set(path) do
    Process.put(@key, path)
    :ok
  end

  @doc """
  Convenient combination of `set/1` and `append/1`.
  """
  @spec set_and_append(path_t(), String.t()) :: :ok
  def set_and_append(path, name) do
    :ok = set(path)
    append(name)
  end

  @doc """
  Returns formatted string of given path's names joined with separator.
  """
  @spec format(path_t(), String.t()) :: String.t()
  def format(path, separator \\ "/") do
    path |> Enum.join(separator)
  end

  @doc """
  Works the same as `format/2` but uses currently stored path
  """
  @spec get_formatted(String.t()) :: String.t()
  def get_formatted(separator \\ "/") do
    Process.get(@key, []) |> format(separator)
  end

  @doc """
  Returns currently stored path.

  If path has not been set, empty list is returned.
  """
  @spec get() :: list(String.t())
  def get(), do: Process.get(@key, [])
end
