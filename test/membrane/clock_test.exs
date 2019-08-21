defmodule Membrane.ClockTest do
  @module Membrane.Clock

  use ExUnit.Case

  test "should calculate proper ratio and send it to subscribers on each (but the first) update" do
    clock = @module.start_link!(time_provider: fn -> receive do: (time: t -> t) end)
    @module.subscribe(clock)
    assert_receive {:membrane_clock_ratio, ^clock, 1}
    send(clock, {:membrane_clock_update, 20})
    send(clock, time: 3)
    refute_receive {:membrane_clock_ratio, ^clock, _ratio}
    send(clock, {:membrane_clock_update, 2})
    send(clock, time: 13)
    assert_receive {:membrane_clock_ratio, ^clock, 2}
    send(clock, {:membrane_clock_update, 1234})
    send(clock, time: 33)
    ratio = Ratio.new(22, 30)
    assert_receive {:membrane_clock_ratio, ^clock, ^ratio}
  end

  test "should handle different ratio formats" do
    use Ratio
    clock = @module.start_link!(time_provider: fn -> receive do: (time: t -> t) end)
    send(clock, {:membrane_clock_update, 5})
    send(clock, time: 5)
    send(clock, {:membrane_clock_update, Ratio.new(1, 3)})
    send(clock, time: 10)
    send(clock, {:membrane_clock_update, {1, 3}})
    send(clock, time: 15)
    send(clock, {:membrane_clock_update, 5})
    send(clock, time: 20)
    @module.subscribe(clock)
    ratio = (5 + Ratio.new(2, 3)) / 15
    assert_receive {:membrane_clock_ratio, ^clock, ^ratio}
  end

  test "should send proper ratio when default time provider is used" do
    clock = @module.start_link!()
    @module.subscribe(clock)
    assert_receive {:membrane_clock_ratio, ^clock, 1}
    send(clock, {:membrane_clock_update, 100})
    Process.send_after(clock, {:membrane_clock_update, 100}, 50)
    Process.send_after(clock, {:membrane_clock_update, 1234}, 100)
    assert_receive {:membrane_clock_ratio, ^clock, ratio}
    assert_in_delta Ratio.to_float(ratio), 2, 0.3
    assert_receive {:membrane_clock_ratio, ^clock, ratio}
    assert_in_delta Ratio.to_float(ratio), 2, 0.3
  end

  describe "should send current ratio once a new subscriber connects" do
    test "when no updates have been sent" do
      clock = @module.start_link!()
      @module.subscribe(clock)
      assert_receive {:membrane_clock_ratio, ^clock, 1}
      refute_receive {:membrane_clock_ratio, ^clock, _ratio}
    end

    test "when one update has been sent" do
      clock = @module.start_link!()
      send(clock, {:membrane_clock_update, 3})
      @module.subscribe(clock)
      assert_receive {:membrane_clock_ratio, ^clock, 1}
      refute_receive {:membrane_clock_ratio, ^clock, _ratio}
    end

    test "when more than one update has been sent" do
      clock = @module.start_link!(time_provider: fn -> receive do: (time: t -> t) end)
      send(clock, {:membrane_clock_update, 20})
      send(clock, time: 3)
      send(clock, {:membrane_clock_update, 1234})
      send(clock, time: 13)
      @module.subscribe(clock)
      assert_receive {:membrane_clock_ratio, ^clock, 2}
      refute_receive {:membrane_clock_ratio, ^clock, _ratio}
    end
  end

  test "all subscribers should receive the same ratio after each update" do
    clock = @module.start_link!(time_provider: fn -> receive do: (time: t -> t) end)

    fn ->
      Task.start_link(fn ->
        @module.subscribe(clock)
        assert_receive {:membrane_clock_ratio, ^clock, 1}
        assert_receive {:membrane_clock_ratio, ^clock, 2}
        ratio = Ratio.new(50, 20)
        assert_receive {:membrane_clock_ratio, ^clock, ^ratio}
      end)
    end
    |> Bunch.Enum.repeat(5)

    send(clock, {:membrane_clock_update, 20})
    send(clock, time: 3)
    send(clock, {:membrane_clock_update, 30})
    send(clock, time: 13)
    send(clock, {:membrane_clock_update, 1234})
    send(clock, time: 23)
  end

  test "should handle subscriptions properly" do
    clock = @module.start_link!()

    check_update = fn ->
      send(clock, {:membrane_clock_update, 42})
      assert_receive {:membrane_clock_ratio, ^clock, _ratio}
      refute_receive {:membrane_clock_ratio, ^clock, _ratio}
    end

    send(clock, {:membrane_clock_update, 42})
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
    send(clock, {:membrane_clock_update, 42})
    refute_receive {:membrane_clock_ratio, ^clock, _ratio}
  end

  test "should unsubscribe upon process death" do
    clock = @module.start_link!()
    send(clock, {:membrane_clock_update, 42})
    Process.sleep(10)
    @module.subscribe(clock)
    assert_receive {:membrane_clock_ratio, ^clock, _ratio}
    @module.subscribe(clock)
    send(clock, {:membrane_clock_update, 42})
    assert_receive {:membrane_clock_ratio, ^clock, _ratio}
    send(clock, {:DOWN, nil, :process, self(), nil})
    send(clock, {:membrane_clock_update, 42})
    refute_receive {:membrane_clock_ratio, ^clock, _ratio}
  end

  test "should ignore unsubscribe from a non-subscribed process" do
    clock = @module.start_link!()
    @module.unsubscribe(clock)
  end
end
