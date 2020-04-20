defmodule Membrane.Helper.GenServer do
  @moduledoc false

  require Logger

  @type genserver_return_t :: {:noreply, any} | {:reply, any, any}

  def noreply({:ok, new_state}), do: {:noreply, new_state}

  def noreply({:ok, new_state}, _old_state), do: {:noreply, new_state}

  def noreply({{:error, reason}, new_state}, old_state) do
    Logger.error("""
    Terminating GenServer, reason: #{inspect(reason)},
    old state: #{inspect(old_state)},
    new state: #{inspect(new_state)}
    """)

    {:stop, {:error, reason}, new_state}
  end

  def noreply({:error, reason}, old_state) do
    Logger.error("""
    Terminating GenServer, reason: #{inspect(reason)},
    old state: #{inspect(old_state)}
    """)

    {:stop, {:error, reason}, old_state}
  end

  def noreply({:stop, _reason, _new_state} = stop, _old_state), do: stop

  def reply({:ok, new_state}), do: {:reply, :ok, new_state}
  def reply({{:ok, v}, new_state}), do: {:reply, {:ok, v}, new_state}
  def reply({:ok, new_state}, _old_state), do: {:reply, :ok, new_state}
  def reply({{:ok, v}, new_state}, _old_state), do: {:reply, {:ok, v}, new_state}

  def reply({{:error, reason}, new_state}, old_state) do
    Logger.error("""
    GenServer returning error reply, reason: #{inspect(reason)}
    old state: #{inspect(old_state)},
    new state: #{inspect(new_state)}
    """)

    {:reply, {:error, reason}, new_state}
  end

  def reply({:error, reason}, old_state) do
    Logger.error("""
    GenServer returning error reply, reason: #{inspect(reason)}
    old state: #{inspect(old_state)}
    """)

    {:reply, {:error, reason}, old_state}
  end
end
