defprotocol Membrane.Core.ParentState do
  alias Membrane.Core.ChildrenController

  @type children_t :: %{ChildrenController.child_name_t() => pid}

  @spec add_child(t, ChildrenController.child_name_t(), pid) :: Type.stateful_try_t(t)
  def add_child(state, child, pid)

  @spec get_child_pid(t, ChildrenController.child_name_t()) :: Type.try_t(pid)
  def get_child_pid(state, child)

  @spec pop_child(t, ChildrenController.child_name_t()) :: Type.stateful_try_t(pid, t)
  def pop_child(state, child)

  @spec get_children_names(t) :: [ChildrenController.child_name_t()]
  def get_children_names(state)

  @spec get_children(t) :: children_t
  def get_children(state)
end

defmodule Membrane.Core.ParentState.Default do
  defmacro __using__(_) do
    quote location: :keep do
      def add_child(%{children: children} = state, child, pid) do
        if Map.has_key?(children, child) do
          {{:error, {:duplicate_child, child}}, state}
        else
          {:ok, %{state | children: children |> Map.put(child, pid)}}
        end
      end

      def get_child_pid(%{children: children}, child) do
        with {:ok, pid} <- children[child] |> Bunch.error_if_nil({:unknown_child, child}),
             do: {:ok, pid}
      end

      def pop_child(%{children: children} = state, child) do
        {pid, children} = children |> Map.pop(child)

        with {:ok, pid} <- pid |> Bunch.error_if_nil({:unknown_child, child}) do
          state = %{state | children: children}
          {{:ok, pid}, state}
        end
      end

      def get_children_names(%{children: children}) do
        children |> Map.keys()
      end

      def get_children(%{children: children}) do
        children
      end
    end
  end
end
