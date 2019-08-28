defmodule Membrane.SyncTest do
  @module Membrane.Sync

  use ExUnit.Case
  use Bunch

  describe "should sync processes" do
    defp gen_times do
      sync = @module.start_link!()

      tasks =
        1..10
        |> Enum.map(fn i ->
          Task.async(fn ->
            :ok = receive do: (:cont -> :ok)
            Process.sleep(10 * i)
            request_time = System.monotonic_time(:millisecond)
            :ok = sync |> @module.sync()
            sync_time = System.monotonic_time(:millisecond)
            {request_time, sync_time}
          end)
        end)
        |> Enum.map(fn task ->
          :ok = sync |> @module.register(task.pid)
          task
        end)

      sync |> @module.activate()

      {request_times, sync_times} =
        tasks
        |> Enum.map(fn task ->
          send(task.pid, :cont)
          task
        end)
        |> Enum.map(&Task.await/1)
        |> Enum.unzip()

      {request_times, sync_times}
    end

    test "synchronization should happen shortly after the last process wants to synchronize" do
      {request_times, sync_times} = gen_times()
      now = System.monotonic_time(:millisecond)
      last_request = request_times |> Enum.min_by(&(now - &1))
      sync_times |> Enum.each(&assert_in_delta(&1, last_request, 10))
    end

    test "synchronization should happen approximately at the same time in each process" do
      {_request_times, sync_times} = gen_times()
      sync_times |> Enum.min_max() ~> ({min, max} -> assert_in_delta(min, max, 5))
    end
  end

  test "should sync only if active" do
    sync = @module.start_link!()

    t1 =
      Task.async(fn ->
        sync |> @module.register()
        receive do: (:cont -> :ok)
      end)

    t2 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        :ok = sync |> @module.sync()
        :ok
      end)

    :ok = Task.await(t2)
    send(t1.pid, :cont)
    :ok = Task.await(t1)
  end

  test "should not sync when inactive even if used to be active" do
    sync = @module.start_link!()
    sync |> @module.activate()
    sync |> @module.deactivate()

    t1 =
      Task.async(fn ->
        receive do: (:cont -> :ok)
      end)

    sync |> @module.register(t1.pid)

    t2 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        :ok = sync |> @module.sync()
        :ok
      end)

    :ok = Task.await(t2)
    send(t1.pid, :cont)
    :ok = Task.await(t1)
  end

  test "should finish syncing currently synced processes upon deactivation" do
    sync = @module.start_link!()

    t1 =
      Task.async(fn ->
        :ok = receive do: (:cont -> :ok)
        Process.sleep(50)
        sync |> @module.deactivate()
        :ok
      end)

    :ok = sync |> @module.register(t1.pid)

    t2 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        :ok = sync |> @module.activate()
        send(t1.pid, :cont)
        :ok = sync |> @module.sync()
        :ok
      end)

    :ok = Task.await(t1)
    :ok = Task.await(t2)
  end

  test "should forget processes that have already exited" do
    sync = @module.start_link!()

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
        :ok
      end)

    :ok = Task.await(t2)
  end

  test "should sync once all non-syncing processes exit" do
    sync = @module.start_link!()

    t1 =
      Task.async(fn ->
        :ok = receive do: (:cont -> :ok)
        Process.sleep(50)
        :ok
      end)

    :ok = sync |> @module.register(t1.pid)

    t2 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        :ok = sync |> @module.activate()
        send(t1.pid, :cont)
        :ok = sync |> @module.sync()
        :ok
      end)

    :ok = Task.await(t1)
    :ok = Task.await(t2)
  end

  test "should exit once all syncees exit iff :empty_exit? flag is present" do
    s1 = @module.start_link!()
    s2 = @module.start_link!(empty_exit?: true)

    [s1, s2]
    |> Enum.each(fn sync ->
      [
        Task.async(fn ->
          receive do: (:cont -> :ok)
          :ok = sync |> @module.activate()
          :ok = sync |> @module.sync()
        end),
        Task.async(fn ->
          receive do: (:cont -> :ok)
        end)
      ]
      |> Enum.map(fn task ->
        :ok = sync |> @module.register(task.pid)
        task
      end)
      |> Enum.map(fn task ->
        send(task.pid, :cont)
        task
      end)
      |> Enum.map(&Task.await/1)
    end)

    Process.sleep(20)
    assert Process.alive?(s1)
    refute Process.alive?(s2)
  end

  test "#{inspect(@module)}.no_sync/0 should sync at once" do
    sync = @module.no_sync()

    t1 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        receive do: (:cont -> :ok)
      end)

    t2 =
      Task.async(fn ->
        :ok = sync |> @module.register()
        :ok = sync |> @module.activate()
        :ok = sync |> @module.sync()
      end)

    :ok = Task.await(t2)
    send(t1.pid, :cont)
    :ok = Task.await(t1)
  end
end
