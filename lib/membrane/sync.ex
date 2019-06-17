defmodule Membrane.Sync do
  use Bunch
  use GenServer
  require Membrane.Core.Message
  alias Membrane.Core.Message
  alias Membrane.Time

  @always :membrane_sync_always

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, %{}, options)
  end

  def start_link!(options \\ []) do
    {:ok, pid} = start_link(options)
    pid
  end

  def register(@always), do: @always

  def register(sync) do
    ref = make_ref()
    :ok = Message.call(sync, :sync_register, ref)
    {ref, sync}
  end

  def ready(@always) do
    Message.send(self(), :sync, @always)
    :ok
  end

  def ready({ref, sync}) do
    Message.call(sync, :sync_ready, ref)
  end

  def sync(@always), do: :ok

  def sync({ref, sync}, options \\ []) do
    delay = options |> Keyword.get(:delay, 0)
    Message.call(sync, :sync, [ref, delay])
  end

  def always(), do: @always

  @impl true
  def init(_opts) do
    {:ok, %{state: :registration, syncees: %{}, max_delay: 0}}
  end

  @impl true
  def handle_call(Message.new(:sync_register, ref), _from, %{state: :registration} = state) do
    state = state |> put_in([:syncees, ref], %{level: %{name: :registered}, delay: nil})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(Message.new(:sync_ready, ref), {pid, _} = _from, %{state: :waiting} = state) do
    case update_level(ref, %{name: :ready, pid: pid}, [:registered], state) do
      {:ok, state} ->
        if all_syncees_level?(state.syncees, [:ready, :sync]) do
          state.syncees
          |> Enum.each(fn
            {ref, %{level: %{name: :ready, pid: pid}}} -> Message.send(pid, :sync, {ref, self()})
            _ -> :ok
          end)
        end

        {:reply, :ok, state}

      {error, state} ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(Message.new(:sync, [ref, delay]), from, %{state: :waiting} = state) do
    case update_level(ref, %{name: :sync, from: from}, [:registered, :ready], state) do
      {:ok, state} ->
        state =
          state
          |> put_in([:syncees, ref, :delay], delay)
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
  def handle_call(Message.new(request, _ref) = message, from, %{state: :registration} = state)
      when request in [:sync, :sync_ready] do
    handle_call(message, from, %{state | state: :waiting})
  end

  @impl true
  def handle_info({:reply, to}, state) do
    to |> Enum.each(&GenServer.reply(&1, :ok))
    {:noreply, state}
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
