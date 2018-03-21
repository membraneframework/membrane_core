defmodule Membrane.Helper.GenServer do
  use Membrane.Mixins.Log, tags: :core

  def noreply({:ok, new_state}), do: {:noreply, new_state}
  def noreply({:ok, new_state}, _old_state), do: {:noreply, new_state}

  def noreply({{:error, reason}, new_state}, old_state) do
    warn_error(
      """
      Terminating GenServer, old state: #{inspect(old_state)}, new state: #{inspect(new_state)}
      """,
      reason
    )

    {:stop, {:error, reason}, new_state}
  end

  def noreply({:error, reason}, old_state) do
    warn_error(
      """
      Terminating GenServer, old state: #{inspect(old_state)}
      """,
      reason
    )

    {:stop, {:error, reason}, old_state}
  end

  def reply({:ok, new_state}), do: {:reply, :ok, new_state}
  def reply({{:ok, v}, new_state}), do: {:reply, {:ok, v}, new_state}
  def reply({:ok, new_state}, _old_state), do: {:reply, :ok, new_state}
  def reply({{:ok, v}, new_state}, _old_state), do: {:reply, {:ok, v}, new_state}

  def reply({{:error, reason}, new_state}, old_state) do
    warn_error(
      """
      GenServer returning error reply, old state: #{inspect(old_state)},
      new state: #{inspect(new_state)}
      """,
      reason
    )

    {:reply, {:error, {:handle_call, reason}}, new_state}
  end

  def reply({:error, reason}, old_state) do
    warn_error(
      """
      GenServer returning error reply, old state: #{inspect(old_state)},
      """,
      reason
    )

    {:reply, {:error, {:handle_call, reason}}, old_state}
  end
end
