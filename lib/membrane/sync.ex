defmodule Membrane.Sync do
  use GenServer

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, %{}, options)
  end

  def register(sync) do
    GenServer.call(sync, :reg)
  end

  def sync(sync) do
    GenServer.call(sync, :sync)
  end

  @impl true
  def init(_opts) do
    {:ok, %{state: :reg, registered: MapSet.new(), synced: MapSet.new()}}
  end

  @impl true
  def handle_call(:reg, {pid, _ref}, %{state: :reg} = state) do
    %{registered: registered} = state

    if not MapSet.member?(registered, pid) do
      {:reply, :ok, %{state | registered: MapSet.put(registered, pid)}}
    else
      {:reply, {:error, :exists}, state}
    end
  end

  @impl true
  def handle_call(:sync, {pid, _ref}, %{state: :sync} = state) do
    %{registered: registered, synced: synced} = state

    present? = MapSet.member?(registered, pid)
    registered = registered |> MapSet.delete(pid)
    synced = synced |> MapSet.put(pid)

    cond do
      not present? ->
        {:reply, {:error, :not_found}, state}

      registered |> Enum.empty?() ->
        synced |> Enum.each(&send(&1, {:sync, self()}))
        {:stop, :normal, :ok, %{state | registered: registered, synced: synced}}

      true ->
        {:reply, :ok, %{state | registered: registered, synced: synced}}
    end
  end

  @impl true
  def handle_call(:sync, from, %{state: :reg} = state) do
    handle_call(:sync, from, %{state | state: :sync})
  end
end
