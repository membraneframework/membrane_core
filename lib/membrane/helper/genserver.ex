defmodule Membrane.Helper.GenServer do
  @moduledoc false

  require Membrane.Logger

  @type genserver_return_t :: {:noreply, any()} | {:reply, any(), any()}

  @spec noreply({:ok, state}) :: {:noreply, state} when state: any()
  def noreply({:ok, new_state}), do: {:noreply, new_state}

  @spec noreply(
          {:ok, state}
          | {:error, state}
          | {{:error, reason}, state}
          | {:stop, reason, new_state :: state},
          old_state :: state
        ) ::
          {:noreply, state} | {:stop, reason, state}
        when state: any(), reason: any()
  def noreply({:ok, new_state}, _old_state), do: {:noreply, new_state}

  def noreply({{:error, reason}, new_state}, old_state) do
    Membrane.Logger.error("""
    Terminating GenServer, reason: #{inspect(reason)},
    old state: #{inspect(old_state, pretty: true)},
    new state: #{inspect(new_state, pretty: true)}
    """)

    {:stop, {:error, reason}, new_state}
  end

  def noreply({:error, reason}, old_state) do
    Membrane.Logger.error("""
    Terminating GenServer, reason: #{inspect(reason)},
    old state: #{inspect(old_state, pretty: true)}
    """)

    {:stop, {:error, reason}, old_state}
  end

  def noreply({:stop, _reason, _new_state} = stop, _old_state), do: stop

  @spec reply({:ok | {:ok, msg}, state}) :: {:reply, :ok | {:ok, msg}, state}
        when msg: any(), state: any()
  def reply({:ok, new_state}), do: {:reply, :ok, new_state}
  def reply({{:ok, v}, new_state}), do: {:reply, {:ok, v}, new_state}

  @spec reply(
          {:ok, new_state}
          | {{:ok, msg}, new_state}
          | {:error, new_state}
          | {{:error, reason}, new_state},
          old_state
        ) ::
          {:reply, :ok | {:error, reason} | {:ok, msg}, new_state}
        when msg: any(), reason: any(), new_state: any(), old_state: any()
  def reply({:ok, new_state}, _old_state), do: {:reply, :ok, new_state}
  def reply({{:ok, v}, new_state}, _old_state), do: {:reply, {:ok, v}, new_state}

  def reply({{:error, reason}, new_state}, old_state) do
    Membrane.Logger.error("""
    GenServer returning error reply, reason: #{inspect(reason)}
    old state: #{inspect(old_state, pretty: true)},
    new state: #{inspect(new_state, pretty: true)}
    """)

    {:reply, {:error, reason}, new_state}
  end

  def reply({:error, reason}, old_state) do
    Membrane.Logger.error("""
    GenServer returning error reply, reason: #{inspect(reason)}
    old state: #{inspect(old_state, pretty: true)}
    """)

    {:reply, {:error, reason}, old_state}
  end
end
