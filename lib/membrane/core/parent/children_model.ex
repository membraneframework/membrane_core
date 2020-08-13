defmodule Membrane.Core.Parent.ChildrenModel do
  @moduledoc false

  alias Membrane.Core.Parent

  @type children_t :: %{Membrane.Child.name_t() => Membrane.ChildEntry.t()}

  @spec add_child(Parent.state_t(), Membrane.Child.name_t(), Membrane.ChildEntry.t()) ::
          {:ok | {:error, {:duplicate_child, Membrane.Child.name_t()}}, Parent.state_t()}
  def add_child(%{children: children} = state, child, data) do
    if Map.has_key?(children, child) do
      {{:error, {:duplicate_child, child}}, state}
    else
      {:ok, %{state | children: children |> Map.put(child, data)}}
    end
  end

  @spec get_child_data(Parent.state_t(), Membrane.Child.name_t()) ::
          {:ok, child_data :: Membrane.ChildEntry.t()}
          | {:error, {:unknown_child, Membrane.Child.name_t()}}
  def get_child_data(%{children: children}, child) do
    children[child] |> Bunch.error_if_nil({:unknown_child, child})
  end

  @spec pop_child(Parent.state_t(), Membrane.Child.name_t()) ::
          {{:ok, child_data :: Membrane.ChildEntry.t()}
           | {:error, {:unknown_child, Membrane.Child.name_t()}}, Parent.state_t()}
  def pop_child(%{children: children} = state, child) do
    {pid, children} = children |> Map.pop(child)

    with {:ok, pid} <- pid |> Bunch.error_if_nil({:unknown_child, child}) do
      state = %{state | children: children}
      {{:ok, pid}, state}
    end
  end

  @spec get_children_names(Parent.state_t()) :: [Membrane.Child.name_t()]
  def get_children_names(%{children: children}) do
    children |> Map.keys()
  end

  @spec get_children(Parent.state_t()) :: children_t
  def get_children(%{children: children}) do
    children
  end

  @spec update_children(Parent.state_t(), fun()) ::
          Parent.state_t()
  def update_children(state, mapper) do
    children =
      state.children
      |> Enum.map(fn {name, entry} -> {name, mapper.(entry)} end)
      |> Enum.into(%{})

    %{state | children: children}
  end

  @spec all?(Parent.state_t(), fun()) :: boolean()
  def all?(state, predicate) do
    state.children
    |> Enum.all?(fn {_k, v} -> predicate.(v) end)
  end
end
