defmodule Membrane.Sync do
  use Bunch
  use GenServer

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, %{}, options)
  end

  def register(sync) do
    GenServer.call(sync, :register)
  end

  def ready(sync) do
    GenServer.call(sync, :ready)
  end

  def sync(sync) do
    GenServer.call(sync, :sync)
  end

  @impl true
  def init(_opts) do
    {:ok, %{state: :registration, syncees: %{}}}
  end

  @impl true
  def handle_call(:register, {pid, _ref}, %{state: :registration} = state) do
    if not Map.has_key?(state.syncees, pid) do
      {:reply, :ok, state |> put_in([:syncees, pid], %{name: :registered})}
    else
      {:reply, {:error, :exists}, state}
    end
  end

  @impl true
  def handle_call(:ready, {pid, _ref}, %{state: :waiting} = state) do
    withl level: {:ok, state} <- update_level(pid, %{name: :ready}, [:registered], state),
          ready: false <- all_syncees_level?(state.syncees, [:ready, :sync]) do
      {:reply, :ok, state}
    else
      level: {error, state} ->
        {:reply, error, state}

      ready: true ->
        state.syncees |> Map.keys() |> Enum.each(&send(&1, {:ready, self()}))
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:sync, {pid, _ref} = from, %{state: :waiting} = state) do
    withl level:
            {:ok, state} <-
              update_level(pid, %{name: :sync, from: from}, [:registered, :ready], state),
          sync: false <- all_syncees_level?(state.syncees, [:sync]) do
      {:noreply, state}
    else
      level: {error, state} ->
        {:reply, error, state}

      sync: true ->
        state
        |> Map.update!(
          :syncees,
          &Bunch.Map.map_values(&1, fn syncee ->
            GenServer.reply(syncee.from, :ok)
            %{name: :registered}
          end)
        )
        ~> {:noreply, &1}
    end
  end

  @impl true
  def handle_call(request, from, %{state: :registration} = state)
      when request in [:sync, :ready] do
    handle_call(request, from, %{state | state: :waiting})
  end

  defp update_level(pid, new_level, supported_levels, state) do
    level = state.syncees[pid]

    cond do
      level |> is_nil -> {{:error, :not_found}, state}
      level.name in supported_levels -> {:ok, state |> put_in([:syncees, pid], new_level)}
      level -> {{:error, invalid_level: level.name}, state}
    end
  end

  defp all_syncees_level?(syncees, levels) do
    syncees |> Map.values() |> Enum.all?(&(&1.name in levels))
  end
end
