defmodule Membrane.Core.Parent.ChildrenModel do
  @moduledoc false

  alias Membrane.Core.Parent
  alias Membrane.Core.Parent.State

  @type children_t :: %{Membrane.Child.name_t() => Parent.Child.resolved_t()}

  @spec add_child(State.t(), Membrane.Child.name_t(), Parent.Child.resolved_t()) ::
          {:ok | {:error, {:duplicate_child, Membrane.Child.name_t()}}, State.t()}
  def add_child(%{children: children} = state, child, data) do
    if Map.has_key?(children, child) do
      {{:error, {:duplicate_child, child}}, state}
    else
      {:ok, %{state | children: children |> Map.put(child, data)}}
    end
  end

  # TODO narrow down data type of child_data
  @spec get_child_data(State.t(), Membrane.Child.name_t()) ::
          {:ok, child_data :: map()} | {:error, {:unknown_child, Membrane.Child.name_t()}}
  def get_child_data(%{children: children}, child) do
    children[child] |> Bunch.error_if_nil({:unknown_child, child})
  end

  @spec pop_child(State.t(), Membrane.Child.name_t()) ::
          {{:ok, child_data :: map()} | {:error, {:unknown_child, Membrane.Child.name_t()}},
           State.t()}
  def pop_child(%{children: children} = state, child) do
    {pid, children} = children |> Map.pop(child)

    with {:ok, pid} <- pid |> Bunch.error_if_nil({:unknown_child, child}) do
      state = %{state | children: children}
      {{:ok, pid}, state}
    end
  end

  @spec get_children_names(State.t()) :: [Membrane.Child.name_t()]
  def get_children_names(%{children: children}) do
    children |> Map.keys()
  end

  @spec get_children(State.t()) :: children_t
  def get_children(%{children: children}) do
    children
  end
end
