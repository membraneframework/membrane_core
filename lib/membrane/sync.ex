defmodule Membrane.Sync do
  use Bunch
  use GenServer
  alias Membrane.Time

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, %{}, options)
  end

  def register(sync) do
    GenServer.call(sync, :register)
  end

  def ready(sync) do
    GenServer.call(sync, :ready)
  end

  def sync(sync, options \\ []) do
    delay = options |> Keyword.get(:delay, 0)
    GenServer.call(sync, {:sync, delay})
  end

  @impl true
  def init(_opts) do
    {:ok, %{state: :registration, syncees: %{}, max_delay: 0}}
  end

  @impl true
  def handle_call(:register, {pid, _ref}, %{state: :registration} = state) do
    if not Map.has_key?(state.syncees, pid) do
      state =
        state
        |> put_in([:syncees, pid], %{level: %{name: :registered}, delay: nil})

      {:reply, :ok, state}
    else
      {:reply, {:error, :exists}, state}
    end
  end

  @impl true
  def handle_call(:ready, {pid, _ref}, %{state: :waiting} = state) do
    case update_level(pid, %{name: :ready}, [:registered], state) do
      {:ok, state} ->
        unless all_syncees_level?(state.syncees, [:ready, :sync]) do
          {:reply, :ok, state}
        else
          state.syncees |> Map.keys() |> Enum.each(&send(&1, {:ready, self()}))
          {:reply, :ok, state}
        end

      {error, state} ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:sync, delay}, {pid, _ref} = from, %{state: :waiting} = state) do
    case update_level(pid, %{name: :sync, from: from}, [:registered, :ready], state) do
      {:ok, state} ->
        state =
          state
          |> put_in([:syncees, pid, :delay], delay)
          |> Map.update!(:max_delay, &max(&1, delay))

        unless all_syncees_level?(state.syncees, [:sync]) do
          {:noreply, state}
        else
          send_sync_replies(state.syncees, state.max_delay)
          state = reset_syncees(state)
          {:noreply, state}
        end

      {error, state} ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(request, from, %{state: :registration} = state)
      when request in [:sync, :ready] do
    handle_call(request, from, %{state | state: :waiting})
  end

  @impl true
  def handle_info({:reply, to}, state) do
    to |> Enum.each(&GenServer.reply(&1, :ok))
    {:noreply, state}
  end

  defp update_level(pid, new_level, supported_levels, state) do
    syncee = state.syncees[pid]

    cond do
      syncee |> is_nil ->
        {{:error, :not_found}, state}

      syncee.level.name in supported_levels ->
        {:ok, state |> put_in([:syncees, pid, :level], new_level)}

      true ->
        {{:error, invalid_level: syncee.level.name}, state}
    end
  end

  defp all_syncees_level?(syncees, levels) do
    syncees |> Map.values() |> Enum.all?(&(&1.level.name in levels))
  end

  defp send_sync_replies(syncees, max_delay) do
    syncees
    |> Map.values()
    |> Enum.group_by(& &1.delay, & &1.level.from)
    |> Enum.each(fn {delay, from} ->
      time = (max_delay - delay) |> Time.to_milliseconds()
      Process.send_after(self(), {:reply, from}, time)
    end)
  end

  defp reset_syncees(state) do
    state
    |> Map.update!(
      :syncees,
      &Bunch.Map.map_values(&1, fn s -> %{s | level: %{name: :registered}} end)
    )
  end
end
