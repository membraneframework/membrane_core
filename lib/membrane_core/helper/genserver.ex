defmodule Membrane.Helper.GenServer do
  use Membrane.Mixins.Log

  def noreply({:ok, new_state}, _old_state), do: {:noreply, new_state}
  def noreply({{:error, reason}, new_state}, old_state) do
    warn_error """
      Terminating GenServer, old state: #{inspect old_state}, new state: #{inspect new_state}
      """, reason
    {:stop, {:error, reason}, new_state}
  end
  def noreply({:error, reason}, old_state) do
    warn_error """
      Terminating GenServer, old state: #{inspect old_state}
      """, reason
    {:stop, {:error, reason}, old_state}
  end

  def reply({:ok, new_state}, _old_state), do: {:reply, :ok, new_state}
  def reply({{:ok, v}, new_state}, _old_state), do: {:reply, {:ok, v}, new_state}
  def reply({{:error, _reason}, _new_state} = result, old_state), do:
    noreply(result, old_state)
  def reply({:error, _reason} = result, old_state), do:
    noreply(result, old_state)
end
