defmodule Membrane.SyncTest do
  @module Membrane.Sync

  use ExUnit.Case
  use Bunch

  describe "should sync processes" do
    defp gen_times do
      sync = @module.start_link!()

      {request_times, sync_times} =
        1..10
        |> Enum.map(fn i ->
          Task.async(fn ->
            ref = sync |> @module.register()
            :ok = ref |> @module.ready()
            :ok = receive do: (:cont -> :ok)
            Process.sleep(10 * i)
            request_time = System.monotonic_time(:millisecond)
            :ok = ref |> @module.sync()
            sync_time = System.monotonic_time(:millisecond)
            {request_time, sync_time}
          end)
        end)
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

  test "should sync only ready processes" do
    sync = @module.start_link!()

    t1 =
      Task.async(fn ->
        sync |> @module.register()
        receive do: (:cont -> :ok)
      end)

    t2 =
      Task.async(fn ->
        ref = sync |> @module.register()
        :ok = ref |> @module.ready()
        :ok = ref |> @module.sync()
        :ok
      end)

    :ok = Task.await(t2)
    send(t1.pid, :cont)
    :ok = Task.await(t1)
  end

  test "should sync only ready processes even if some used to be ready" do
    sync = @module.start_link!()

    t1 =
      Task.async(fn ->
        ref = sync |> @module.register()
        :ok = ref |> @module.ready()
        :ok = ref |> @module.unready()
        receive do: (:cont -> :ok)
      end)

    t2 =
      Task.async(fn ->
        ref = sync |> @module.register()
        :ok = ref |> @module.ready()
        :ok = ref |> @module.sync()
        :ok
      end)

    :ok = Task.await(t2)
    send(t1.pid, :cont)
    :ok = Task.await(t1)
  end

  test "should forget processes that have already exited" do
    sync = @module.start_link!()

    t1 =
      Task.async(fn ->
        ref = sync |> @module.register()
        :ok = ref |> @module.ready()
        :ok
      end)

    :ok = Task.await(t1)

    t2 =
      Task.async(fn ->
        ref = sync |> @module.register()
        :ok = ref |> @module.ready()
        :ok = ref |> @module.sync()
        :ok
      end)

    :ok = Task.await(t2)
  end

  test "should sync once all non-syncing processes exit" do
    sync = @module.start_link!()

    t1 =
      Task.async(fn ->
        ref = sync |> @module.register()
        :ok = ref |> @module.ready()
        :ok = receive do: (:cont -> :ok)
        Process.sleep(50)
        :ok
      end)

    t2 =
      Task.async(fn ->
        ref = sync |> @module.register()
        :ok = ref |> @module.ready()
        send(t1.pid, :cont)
        :ok = ref |> @module.sync()
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
          ref = sync |> @module.register()
          :ok = ref |> @module.ready()
          :ok = ref |> @module.sync()
          receive do: (:cont -> :ok)
        end),
        Task.async(fn ->
          ref = sync |> @module.register()
          :ok = ref |> @module.ready()
          receive do: (:cont -> :ok)
        end),
        Task.async(fn ->
          sync |> @module.register()
          receive do: (:cont -> :ok)
        end)
      ]
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

  test "#{inspect(@module)}.always/0 should sync always" do
    sync = @module.always()

    t1 =
      Task.async(fn ->
        ref = sync |> @module.register()
        :ok = ref |> @module.ready()
        receive do: (:cont -> :ok)
      end)

    t2 =
      Task.async(fn ->
        ref = sync |> @module.register()
        :ok = ref |> @module.ready()
        :ok = ref |> @module.sync()
      end)

    :ok = Task.await(t2)
    send(t1.pid, :cont)
    :ok = Task.await(t1)
  end
end
