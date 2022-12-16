defmodule Membrane.Testing.Utils do
  @moduledoc """
  Provides functions facilitating testing Membrane components.
  """

  alias Membrane.Child

  require Membrane.Core.Message, as: Message

  @doc """
  Gets pid of child `child_ref` of parent `parent_pid`.

  Returns
   * `{:ok, child_pid}`, if parent contains child with provided name
   * `{:error, :child_not_found}`, if parent does not have such a child
   * `{:error, :parent_not_alive}`, if parent is not alive
  """
  @spec get_child_pid(pid(), Child.ref_t()) ::
          {:ok, pid()} | {:error, :parent_not_alive | :child_not_found}
  def get_child_pid(parent_pid, child_ref) do
    msg = Message.new(:get_child_pid, child_ref)

    try do
      GenServer.call(parent_pid, msg)
    catch
      :exit, {:noproc, {GenServer, :call, [^parent_pid, ^msg | _tail]}} ->
        {:error, :parent_not_alive}
    end
  end

  @doc """
  Returns pid of child `child_ref` of parent `parent_pid`.

  Raises an error, if parent is not alive or doesn't have specified child.
  """
  @spec get_child_pid!(pid(), Child.ref_t()) :: pid()
  def get_child_pid!(parent_pid, child_ref) do
    {:ok, child_pid} = get_child_pid(parent_pid, child_ref)
    child_pid
  end
end
