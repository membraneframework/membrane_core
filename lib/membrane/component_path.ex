defmodule Membrane.ComponentPath do
  @moduledoc """
  A list consisting of following pipeline/bin/element names down the assembled pipeline.

  It traces element's path inside a pipeline.
  Information is being stored in a process dictionary and can be set/appended to.
  """

  @typedoc @moduledoc
  @type path :: list(String.t())

  @key :membrane_path

  @doc """
  Sets current path.

  If path had already existed then replaces it.
  """
  @spec set(path()) :: :ok
  def set(path) do
    Process.put(@key, path)
    :ok
  end

  @doc """
  Returns formatted string of given path's names.
  """
  @spec format(path()) :: String.t()
  def format(path) do
    Enum.join(path)
  end

  @doc """
  Works the same way as `format/1` but uses currently stored path.
  """
  @spec get_formatted() :: String.t()
  def get_formatted() do
    get() |> format()
  end

  @doc """
  Returns currently stored path.

  If path has not been set, empty list is returned.
  """
  @spec get() :: path()
  def get(), do: Process.get(@key, [])
end
