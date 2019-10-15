defmodule Membrane.Core.Parent.ChildrenModel do
  @moduledoc false

  alias Bunch.Type
  alias Membrane.{Child, Clock, Sync}
  alias Membrane.Core.{Bin, Pipeline}

  @type child_t :: {Child.name_t(), pid}
  @type child_data :: %{clock: Clock.t(), pid: pid, sync: Sync.t()}
  @type children_t :: %{Child.name_t() => child_data()}

  @type t :: Bin.State.t() | Pipeline.State.t()

  @spec add_child(t, Child.name_t(), child_data :: map()) :: Type.stateful_try_t(t)
  def add_child(%{children: children} = state, child, data) do
    if Map.has_key?(children, child) do
      {{:error, {:duplicate_child, child}}, state}
    else
      {:ok, %{state | children: children |> Map.put(child, data)}}
    end
  end

  # TODO narrow down data type of child_data
  @spec get_child_data(t, Child.name_t()) :: {:ok, child_data :: map()} | {:error, any}
  def get_child_data(%{children: children}, child) do
    children[child] |> Bunch.error_if_nil({:unknown_child, child})
  end

  @spec pop_child(t, Child.name_t()) :: Type.stateful_try_t(map(), t)
  def pop_child(%{children: children} = state, child) do
    {pid, children} = children |> Map.pop(child)

    with {:ok, pid} <- pid |> Bunch.error_if_nil({:unknown_child, child}) do
      state = %{state | children: children}
      {{:ok, pid}, state}
    end
  end

  @spec get_children_names(t) :: [Child.name_t()]
  def get_children_names(%{children: children}) do
    children |> Map.keys()
  end

  @spec get_children(t) :: children_t
  def get_children(%{children: children}) do
    children
  end
end
