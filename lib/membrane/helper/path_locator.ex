defmodule Membrane.Helper.PathLocator do
  @moduledoc false

  # Helper module for tracing element's path inside of a pipeline.
  # Path is a list consisted of following pipeline/bin/element names down the proper pipeline.
  # Information is being stored in a process dictionary and can be set/appended to.

  @type path_t :: list(String.t())

  @key :membrane_path

  @spec append_path(String.t()) :: :ok
  def append_path(name) do
    path = Process.get(@key, [])
    Process.put(@key, path ++ [name])
    :ok
  end

  @spec set_path(path_t) :: :ok
  def set_path(path) do
    Process.put(@key, path)
    :ok
  end

  def set_and_append_path(path, name) do
    :ok = set_path(path)
    append_path(name)
  end

  @spec get_formatted_path() :: String.t()
  def get_formatted_path() do
    Process.get(@key, []) |> Enum.join("/")
  end

  @spec get_formatted_path(path_t()) :: String.t()
  def get_formatted_path(path) do
    path |> Enum.join("/")
  end

  @spec get_path() :: list(String.t())
  def get_path(), do: Process.get(@key, [])
end
