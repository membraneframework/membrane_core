defmodule Membrane.Testing.Utils do
  @moduledoc """
  Provides functions facilitating testing Membrane components.
  """

  alias Membrane.Child

  @doc """
  Gets pid of child `child_name` of parent `parent_pid`.

  If child is inside child group, group name has to be passed in `opts`.

  Returns
   * `{:ok, child_pid}`, if parent contains child with provided name
   * `{:error, :child_not_found}`, if parent does not have such a child
   * `{:error, :parent_not_alive}`, if parent is not alive
  """
  @spec get_child_pid(pid(), Child.name_t(), Child.child_ref_options_t()) ::
          {:ok, pid()} | {:error, :parent_not_alive | :child_not_found}
  def get_child_pid(parent_pid, child_name, opts \\ []) do
    child_ref = Child.ref(child_name, opts)

    try do
      case :sys.get_state(parent_pid) do
        %{children: %{^child_ref => %{pid: child_pid}}} ->
          {:ok, child_pid}

        _other ->
          {:error, :child_not_found}
      end
    catch
      :exit, {:noproc, {:sys, :get_state, [^parent_pid]}} ->
        {:error, :parent_not_alive}
    end
  end

  @doc """
  Gets pid of child `child_name` of parent `parent_pid` and returns it.

  If child is inside child group, group name has to be passed in `opts`.

  Raises an error, if parent is not alive or doesn't have specified child.
  """
  @spec get_child_pid!(pid(), Child.name_t(), Child.child_ref_options_t()) :: pid()
  def get_child_pid!(parent_pid, child_name, opts \\ []) do
    {:ok, child_pid} = get_child_pid(parent_pid, child_name, opts)
    child_pid
  end
end
