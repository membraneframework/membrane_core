defmodule Membrane.ClockTest.Sync do
  use ExUnit.Case, async: false

  @module Membrane.Clock

  @initial_ratio Ratio.new(1)

  test "should send proper ratio when default time provider is used" do
    ratio_error = 0.3
    {:ok, clock} = @module.start_link()
    @module.subscribe(clock)
    assert_receive {:membrane_clock_ratio, ^clock, @initial_ratio}
    send(clock, {:membrane_clock_update, 100})
    Process.send_after(clock, {:membrane_clock_update, 100}, 50)
    Process.send_after(clock, {:membrane_clock_update, random_time()}, 100)
    assert_receive {:membrane_clock_ratio, ^clock, ratio}
    assert_in_delta Ratio.to_float(ratio), 100 / 50, ratio_error
    assert_receive {:membrane_clock_ratio, ^clock, ratio}
    assert_in_delta Ratio.to_float(ratio), 100 / 50, ratio_error
  end

  defp random_time, do: :rand.uniform(10_000)
end

defmodule Membrane.ClockTest do
  use ExUnit.Case, async: true

  @module Membrane.Clock

  @initial_ratio Ratio.new(1)

  test "should calculate proper ratio and send it to subscribers on each (but the first) update" do
    {:ok, clock} =
      @module.start_link(time_provider: fn -> receive do: (time: t -> ms_to_ns(t)) end)

    @module.subscribe(clock)
    assert_receive {:membrane_clock_ratio, ^clock, @initial_ratio}
    send(clock, {:membrane_clock_update, 20})
    send(clock, time: 3)
    refute_receive {:membrane_clock_ratio, ^clock, _ratio}
    send(clock, {:membrane_clock_update, 2})
    send(clock, time: 13)
    two = Ratio.new(2)
    assert_receive {:membrane_clock_ratio, ^clock, ^two}
    send(clock, {:membrane_clock_update, random_time()})
    send(clock, time: 33)
    ratio = Ratio.new(20 + 2, 33 - 3)
    assert_receive {:membrane_clock_ratio, ^clock, ^ratio}
  end

  test "should handle different ratio formats" do
    {:ok, clock} =
      @module.start_link(time_provider: fn -> receive do: (time: t -> ms_to_ns(t)) end)

    send(clock, {:membrane_clock_update, 5})
    send(clock, time: 5)
    send(clock, {:membrane_clock_update, Ratio.new(1, 3)})
    send(clock, time: 10)
    send(clock, {:membrane_clock_update, {1, 3}})
    send(clock, time: 15)
    send(clock, {:membrane_clock_update, 5})
    send(clock, time: 20)
    @module.subscribe(clock)
    two = Ratio.new(2)
    five = Ratio.new(5)
    ratio = Ratio.div(Ratio.add(five, Ratio.mult(Ratio.new(1, 3), two)), Ratio.new(20 - 5))
    assert_receive {:membrane_clock_ratio, ^clock, ^ratio}
  end

  describe "should send current ratio once a new subscriber connects" do
    test "when no updates have been sent" do
      {:ok, clock} = @module.start_link()
      @module.subscribe(clock)
      assert_receive {:membrane_clock_ratio, ^clock, @initial_ratio}
      refute_receive {:membrane_clock_ratio, ^clock, _ratio}
    end

    test "when one update has been sent" do
      {:ok, clock} = @module.start_link()
      send(clock, {:membrane_clock_update, random_time()})
      @module.subscribe(clock)
      assert_receive {:membrane_clock_ratio, ^clock, @initial_ratio}
      refute_receive {:membrane_clock_ratio, ^clock, _ratio}
    end

    test "when more than one update has been sent" do
      {:ok, clock} =
        @module.start_link(time_provider: fn -> receive do: (time: t -> ms_to_ns(t)) end)

      send(clock, {:membrane_clock_update, 20})
      send(clock, time: 3)
      send(clock, {:membrane_clock_update, random_time()})
      send(clock, time: 13)
      @module.subscribe(clock)
      ratio = Ratio.new(20, 13 - 3)
      assert_receive {:membrane_clock_ratio, ^clock, ^ratio}
      refute_receive {:membrane_clock_ratio, ^clock, _ratio}
    end
  end

  test "all subscribers should receive the same ratio after each update" do
    {:ok, clock} = @module.start_link(time_provider: fn -> receive do: (time: t -> t) end)

    fn ->
      Task.start_link(fn ->
        @module.subscribe(clock)
        assert_receive {:membrane_clock_ratio, ^clock, @initial_ratio}
        ratio = Ratio.new(20, 13 - 3)
        assert_receive {:membrane_clock_ratio, ^clock, ^ratio}
        ratio = Ratio.new(20 + 30, 23 - 3)
        assert_receive {:membrane_clock_ratio, ^clock, ^ratio}
      end)
    end
    |> Bunch.Enum.repeat(5)

    send(clock, {:membrane_clock_update, 20})
    send(clock, time: 3)
    send(clock, {:membrane_clock_update, 30})
    send(clock, time: 13)
    send(clock, {:membrane_clock_update, random_time()})
    send(clock, time: 23)
  end

  test "should handle subscriptions properly" do
    {:ok, clock} = @module.start_link()

    update = random_time()

    check_update = fn ->
      send(clock, {:membrane_clock_update, update})
      assert_receive {:membrane_clock_ratio, ^clock, _ratio}
      refute_receive {:membrane_clock_ratio, ^clock, _ratio}
    end

    send(clock, {:membrane_clock_update, update})
    refute_receive {:membrane_clock_ratio, ^clock, _ratio}

    @module.subscribe(clock)
    assert_receive {:membrane_clock_ratio, ^clock, _ratio}
    refute_receive {:membrane_clock_ratio, ^clock, _ratio}

    @module.subscribe(clock)
    refute_receive {:membrane_clock_ratio, ^clock, _ratio}
    check_update.()

    @module.unsubscribe(clock)
    check_update.()

    @module.unsubscribe(clock)
    send(clock, {:membrane_clock_update, update})
    refute_receive {:membrane_clock_ratio, ^clock, _ratio}
  end

  test "should unsubscribe upon process death" do
    {:ok, clock} = @module.start_link()
    update = random_time()
    send(clock, {:membrane_clock_update, update})
    Process.sleep(10)
    @module.subscribe(clock)
    assert_receive {:membrane_clock_ratio, ^clock, _ratio}
    @module.subscribe(clock)
    send(clock, {:membrane_clock_update, update})
    assert_receive {:membrane_clock_ratio, ^clock, _ratio}
    send(clock, {:DOWN, nil, :process, self(), nil})
    send(clock, {:membrane_clock_update, update})
    refute_receive {:membrane_clock_ratio, ^clock, _ratio}
  end

  test "should ignore unsubscribe from a non-subscribed process" do
    {:ok, clock} = @module.start_link()
    @module.unsubscribe(clock)
  end

  describe "Clock election in parent" do
    alias Membrane.ChildEntry
    alias Membrane.Clock
    alias Membrane.Core.Parent.ClockHandler
    alias Membrane.Core.Pipeline.State

    test "when provider is specified" do
      {:ok, clock} = Clock.start_link()
      {:ok, proxy_clock} = Clock.start_link(proxy: true)

      children = [
        %ChildEntry{name: :el1, pid: :c.pid(0, 1, 0)},
        %ChildEntry{name: :el2, clock: clock, pid: :c.pid(0, 2, 0)}
      ]

      dummy_pipeline_state =
        struct(State,
          module: __MODULE__,
          synchronization: %{clock_proxy: proxy_clock}
        )

      assert %State{
               synchronization: %{clock_proxy: result_proxy, clock_provider: result_provider}
             } = ClockHandler.choose_clock(children, :el2, dummy_pipeline_state)

      assert %{choice: :manual, clock: ^clock, provider: :el2} = result_provider
      assert ^proxy_clock = result_proxy
    end

    test "when provider is specified but it has no clock" do
      {:ok, clock} = Clock.start_link()
      {:ok, proxy_clock} = Clock.start_link(proxy: true)

      children = [
        %ChildEntry{name: :el1, pid: :c.pid(0, 1, 0)},
        %ChildEntry{name: :el2, clock: clock, pid: :c.pid(0, 2, 0)}
      ]

      dummy_pipeline_state =
        struct(State,
          module: __MODULE__,
          synchronization: %{clock_proxy: proxy_clock, clock_provider: %{choice: :auto}}
        )

      assert_raise Membrane.ParentError, ~r/.*el1.*clock provider/, fn ->
        ClockHandler.choose_clock(children, :el1, dummy_pipeline_state)
      end
    end

    test "when provider is not specified and there are multiple clock providers among children" do
      {:ok, clock} = Clock.start_link()
      {:ok, clock2} = Clock.start_link()
      {:ok, proxy_clock} = Clock.start_link(proxy: true)

      children = [
        %ChildEntry{name: :el1, pid: :c.pid(0, 1, 0)},
        %ChildEntry{name: :el2, clock: clock, pid: :c.pid(0, 2, 0)},
        %ChildEntry{name: :el3, clock: clock2, pid: :c.pid(0, 3, 0)}
      ]

      dummy_pipeline_state =
        struct(State,
          module: __MODULE__,
          synchronization: %{clock_proxy: proxy_clock, clock_provider: %{choice: :auto}}
        )

      assert_raise Membrane.ParentError, ~r/.*multiple components.*/, fn ->
        ClockHandler.choose_clock(children, nil, dummy_pipeline_state)
      end
    end

    test "when there is no clock provider and there is exactly one clock provider among children" do
      {:ok, clock} = Clock.start_link()
      {:ok, proxy_clock} = Clock.start_link(proxy: true)

      children = [
        %ChildEntry{name: :el1, pid: :c.pid(0, 1, 0)},
        %ChildEntry{name: :el2, clock: clock, pid: :c.pid(0, 2, 0)},
        %ChildEntry{name: :el3, pid: :c.pid(0, 3, 0)}
      ]

      dummy_pipeline_state =
        struct(State,
          module: __MODULE__,
          synchronization: %{clock_proxy: proxy_clock, clock_provider: %{choice: :auto}}
        )

      assert %State{
               synchronization: %{clock_proxy: result_proxy, clock_provider: result_provider}
             } = ClockHandler.choose_clock(children, nil, dummy_pipeline_state)

      assert %{choice: :auto, clock: ^clock, provider: :el2} = result_provider
      assert ^proxy_clock = result_proxy
    end
  end

  defp random_time, do: :rand.uniform(10_000)

  defp ms_to_ns(e), do: e * 1_000_000
end
