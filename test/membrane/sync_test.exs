defmodule Membrane.SyncTest do
  use Bunch
  use ExUnit.Case, async: true

  @module Membrane.Sync

  @task_number 10
  @sync_delay 1
  @error 10

  @long_time 50

  describe "should sync processes" do
    defp requester_task(sync, time_multiplier) do
      spawn_paused_task(fn ->
        Process.sleep(10 * time_multiplier)
        request_time = System.monotonic_time(:millisecond)
        :ok = sync |> @module.sync()
        sync_time = System.monotonic_time(:millisecond)
        {request_time, sync_time}
      end)
    end

    defp gen_times do
      {:ok, sync} = @module.start_link()

      tasks =
        1..@task_number
        |> Enum.map(&requester_task(sync, &1))

      tasks
      |> Enum.each(fn task -> :ok = @module.register(sync, task.pid) end)

      @module.activate(sync)

      tasks |> Enum.each(&continue_task/1)

      {request_times, sync_times} =
        tasks
        |> Enum.map(&Task.await/1)
        |> Enum.unzip()

      {request_times, sync_times}
    end

    test "synchronization should happen shortly after the last process wants to synchronize" do
      {request_times, sync_times} = gen_times()
      now = System.monotonic_time(:millisecond)
      last_request = request_times |> Enum.min_by(&(now - &1))

      sync_times
      |> Enum.each(&assert_in_delta(&1, last_request, @task_number * @sync_delay + @error))
    end

    test "synchronization should happen approximately at the same time in each process" do
      {_request_times, sync_times} = gen_times()
      sync_times |> Enum.min_max() ~> ({min, max} -> assert_in_delta(min, max, @sync_delay))
    end
  end

  test "should sync only if active, otherwise sync returns immediately" do
    {:ok, sync} = @module.start_link()

    t1 =
      Task.async(fn ->
        sync |> @module.register()
        receive do: (:continue -> :ok)
      end)

    t2 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        :ok = sync |> @module.sync()
      end)

    :ok = Task.await(t2)
    send(t1.pid, :continue)
    :ok = Task.await(t1)
  end

  test "should not sync when inactive even if used to be active" do
    {:ok, sync} = @module.start_link()
    sync |> @module.activate()
    sync |> @module.deactivate()

    t1 = spawn_paused_task(fn -> :ok end)

    sync |> @module.register(t1.pid)

    t2 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        :ok = sync |> @module.sync()
      end)

    :ok = Task.await(t2)
    continue_task(t1)
    :ok = Task.await(t1)
  end

  test "should finish syncing currently synced processes upon deactivation" do
    {:ok, sync} = @module.start_link()

    t1 =
      spawn_paused_task(fn ->
        Process.sleep(@long_time)
        sync |> @module.deactivate()
        :ok
      end)

    :ok = sync |> @module.register(t1.pid)

    t2 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        :ok = sync |> @module.activate()
        continue_task(t1)
        :ok = sync |> @module.sync()
      end)

    :ok = Task.await(t1)
    :ok = Task.await(t2)
  end

  test "should forget processes that have already exited" do
    {:ok, sync} = @module.start_link()

    t1 =
      Task.async(fn ->
        :ok = sync |> @module.register()
      end)

    :ok = Task.await(t1)

    t2 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        :ok = sync |> @module.activate()
        :ok = sync |> @module.sync()
      end)

    :ok = Task.await(t2)
  end

  test "should sync once all non-syncing processes exit" do
    {:ok, sync} = @module.start_link()

    t1 = spawn_paused_task(fn -> Process.sleep(@long_time) end)

    :ok = sync |> @module.register(t1.pid)

    t2 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        :ok = sync |> @module.activate()
        continue_task(t1)
        :ok = sync |> @module.sync()
      end)

    :ok = Task.await(t1)
    :ok = Task.await(t2)
  end

  defp register_activate_sync(sync) do
    t1 =
      spawn_paused_task(fn ->
        :ok = sync |> @module.activate()
        :ok = sync |> @module.sync()
      end)

    t2 = spawn_paused_task(fn -> :ok end)

    for t <- [t1, t2] do
      :ok = sync |> @module.register(t.pid)
    end

    for t <- [t1, t2] do
      continue_task(t)
    end
    |> Enum.map(&Task.await/1)
  end

  test "should exit once all syncees exit if :empty_exit? flag is present" do
    {:ok, sync} = @module.start_link(empty_exit?: true)

    register_activate_sync(sync)

    Process.sleep(@long_time)
    refute Process.alive?(sync)
  end

  test "should not exit after all syncees exit if :empty_exit? flag is not present" do
    {:ok, sync} = @module.start_link()

    register_activate_sync(sync)

    Process.sleep(@long_time)
    assert Process.alive?(sync)
  end

  test "#{inspect(@module)}.no_sync/0 makes call to sync return immediately" do
    sync = @module.no_sync()

    t1 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        receive do: (:continue -> :ok)
      end)

    t2 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        :ok = sync |> @module.activate()
        :ok = sync |> @module.sync()
      end)

    :ok = Task.await(t2)
    send(t1.pid, :continue)
    :ok = Task.await(t1)
  end

  defp spawn_paused_task(task_fun) do
    Task.async(fn ->
      :ok = receive do: (:continue -> :ok)
      task_fun.()
    end)
  end

  defp continue_task(task) do
    send(task.pid, :continue)
    task
  end
end
