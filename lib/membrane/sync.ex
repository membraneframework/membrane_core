defmodule Membrane.Sync do
  @moduledoc """
  Sync allows to synchronize multiple processes, so that they performed their jobs
  at the same time.

  The flow of usage goes as follows:
  - Processes register themselves in Sync, using `register/2`.
  - When a process is ready to synchronize, it invokes `ready/1`. When a process
  is ready, it is assumed it is going to invoke `sync/2` approximately at the same
  time as all other ready processes.
  - If a process becomes no longer ready, it should invoke `unready/1`.
  - Once a process needs to sync, it invokes `sync/2`, which results in blocking
  until all ready processes invoke `sync/2`.
  - Once all the ready processes invoke `sync/2`, the calls return, and they become
  registered again.
  - Once a process exits, it is automatically unregistered.

  """
  use Bunch
  use GenServer
  require Membrane.Core.Message
  alias Membrane.Core.Message
  alias Membrane.Time

  @always :membrane_sync_always

  @type t :: pid | :membrane_sync_always
  @type ref_t :: {reference, pid} | :membrane_sync_always
  @type level_t :: :registered | :ready
  @type result_t :: :ok | {:error, :not_found | [invalid_level: level_t]}

  @doc """
  Starts a Sync process linked to the current process.

  ## Options
  - :empty_exit? - if true, Sync automatically exits when all syncees exit;
    defaults to false

  """
  @spec start_link([empty_exit?: boolean], GenServer.options()) :: GenServer.on_start()
  def start_link(options \\ [], gen_server_options \\ []) do
    GenServer.start_link(__MODULE__, options, gen_server_options)
  end

  def start_link!(options \\ [], gen_server_options \\ []) do
    {:ok, pid} = start_link(options, gen_server_options)
    pid
  end

  @spec register(t, pid) :: ref_t
  def register(sync, pid \\ self())

  def register(@always, _pid), do: @always

  def register(sync, pid) do
    ref = make_ref()
    :ok = Message.call(sync, :sync_register, [ref, pid])
    {ref, sync}
  end

  @spec unready(ref_t) :: result_t
  def unready(@always), do: :ok

  def unready({ref, sync}) do
    Message.call(sync, :sync_unready, ref)
  end

  @spec ready(ref_t) :: result_t
  def ready(@always), do: :ok

  def ready({ref, sync}) do
    Message.call(sync, :sync_ready, ref)
  end

  @spec sync(ref_t) :: result_t
  def sync(@always), do: :ok

  def sync({ref, sync}, options \\ []) do
    latency = options |> Keyword.get(:latency, 0)
    Message.call(sync, :sync, [ref, latency])
  end

  def always(), do: @always

  @impl true
  def init(opts) do
    {:ok,
     %{
       state: :init,
       syncees: %{},
       syncees_pids: %{},
       empty_exit?: opts |> Keyword.get(:empty_exit?, false)
     }}
  end

  @impl true
  def handle_call(Message.new(:sync_register, [ref, pid]), _from, state) do
    Process.monitor(pid)

    state =
      state
      |> put_in([:syncees, ref], %{level: %{name: :registered}, latency: 0})
      |> put_in([:syncees_pids, pid], ref)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(Message.new(:sync_ready, ref), _from, %{state: :waiting} = state) do
    case update_level(ref, %{name: :ready}, [:registered], state) do
      {:ok, state} -> {:reply, :ok, state}
      {{:error, reason}, state} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(Message.new(:sync_unready, ref), _from, state) do
    case update_level(ref, %{name: :registered}, [:registered, :ready], state) do
      {:ok, %{state: :waiting} = state} ->
        state = state |> check_and_handle_sync()
        {:reply, :ok, state}

      {:ok, state} ->
        {:reply, :ok, state}

      {{:error, reason}, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(Message.new(:sync, [ref, latency]), from, %{state: :waiting} = state) do
    case update_level(ref, %{name: :sync, from: from}, [:ready], state) do
      {:ok, state} ->
        state = state |> put_in([:syncees, ref, :latency], latency) |> check_and_handle_sync()
        {:noreply, state}

      {error, state} ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(Message.new(request, _ref) = message, from, %{state: :init} = state)
      when request in [:sync, :sync_ready] do
    handle_call(message, from, %{state | state: :waiting})
  end

  @impl true
  def handle_info({:reply, to}, state) do
    to |> Enum.each(&GenServer.reply(&1, :ok))
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {ref, state} = state |> pop_in([:syncees_pids, pid])
    state = state |> Bunch.Access.delete_in([:syncees, ref]) |> check_and_handle_sync()

    if state.empty_exit? and state.syncees |> Enum.empty?() do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  defp update_level(ref, new_level, supported_levels, state) do
    syncee = state.syncees[ref]

    cond do
      syncee |> is_nil ->
        {{:error, :not_found}, state}

      syncee.level.name in supported_levels ->
        {:ok, state |> put_in([:syncees, ref, :level], new_level)}

      true ->
        {{:error, invalid_level: syncee.level.name}, state}
    end
  end

  defp check_and_handle_sync(state) do
    unless all_syncees_level?(state.syncees, [:sync, :registered]) do
      state
    else
      send_sync_replies(state.syncees)
      state = reset_syncees(state)
      %{state | state: :init}
    end
  end

  defp all_syncees_level?(syncees, levels) do
    syncees |> Map.values() |> Enum.all?(&(&1.level.name in levels))
  end

  defp send_sync_replies(syncees) do
    max_latency = syncees |> Map.values() |> Enum.map(& &1.latency) |> Enum.max(fn -> 0 end)

    syncees
    |> Map.values()
    |> Enum.filter(&(&1.level.name == :sync))
    |> Enum.group_by(& &1.latency, & &1.level.from)
    |> Enum.each(fn {latency, from} ->
      time = (max_latency - latency) |> Time.to_milliseconds()
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
