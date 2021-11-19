defmodule StructBehaviour do
  @callback __struct__() :: struct()
  @callback __struct__(kv :: [atom | {atom, any()}]) :: struct()
end

defmodule Membrane.FilterAggregatorTest do
  use ExUnit.Case, async: true

  import Mox

  alias Membrane.Buffer
  alias Membrane.Caps.Mock, as: MockCaps
  alias Membrane.FilterAggregator, as: TestedModule

  @moduletag :focus

  setup_all do
    behaviours = [
      Membrane.Filter,
      Membrane.Element.Base,
      Membrane.Element.WithInputPads,
      Membrane.Element.WithOutputPads,
      StructBehaviour
    ]

    defmock(FilterA, for: behaviours)
    defmock(FilterB, for: behaviours)

    stage_opts = %TestedModule{
      filters: [
        a: %{__struct__: FilterA},
        b: %{__struct__: FilterB}
      ]
    }

    states = [
      {:a, FilterA, %{module: FilterA, state: nil}},
      {:b, FilterB, %{module: FilterB, state: nil}}
    ]

    [filters: [FilterA, FilterB], stage_opts: stage_opts, states: states]
  end

  setup %{filters: filters} do
    filters
    |> Enum.each(fn filter ->
      stub(filter, :__struct__, fn kv -> kv |> Map.new() |> Map.put(:__struct__, filter) end)
    end)
  end

  setup :verify_on_exit!

  test "handle_init sets inital states", ctx do
    ctx.filters
    |> Enum.each(fn filter ->
      expect(filter, :handle_init, fn %^filter{} -> {:ok, %{module: filter}} end)
    end)

    assert {:ok, %{states: result}} = TestedModule.handle_init(ctx.stage_opts)

    assert result == [{:a, FilterA, %{module: FilterA}}, {:b, FilterB, %{module: FilterB}}]
  end

  test "handle_prepared_to_playing with caps sending", ctx do
    expect(FilterA, :handle_prepared_to_playing, fn _ctx, %{module: FilterA} = state ->
      {{:ok, caps: {:output, %MockCaps{integer: 1}}}, state}
    end)

    expect(FilterB, :handle_caps, fn :input, %MockCaps{integer: 1}, _ctx, state ->
      {{:ok, caps: {:output, %MockCaps{integer: 2}}}, %{state | state: :caps_sent}}
    end)

    expect(FilterB, :handle_prepared_to_playing, fn _ctx, state ->
      # ensure proper callbacks order
      assert state == %{module: FilterB, state: :caps_sent}
      {:ok, state}
    end)

    assert {{:ok, actions}, %{states: states}} =
             TestedModule.handle_prepared_to_playing(%{}, %{states: ctx.states})

    assert actions == [caps: {:output, %MockCaps{integer: 2}}]

    assert [{:a, FilterA, state_a}, {:b, FilterB, state_b}] = states
    assert state_a == %{module: FilterA, state: nil}
    assert state_b == %{module: FilterB, state: :caps_sent}
  end

  test "handle_process_list splitting and mapping buffers", ctx do
    test_range = 1..10
    buffers = test_range |> Enum.map(&%Buffer{payload: <<&1>>})

    expect(FilterA, :handle_process_list, fn :input, buffers, _ctx, %{module: FilterA} = state ->
      args_list = buffers |> Enum.map(&[:input, &1])
      {{:ok, split: {:handle_process, args_list}}, state}
    end)

    expect(FilterA, :handle_process, Enum.count(test_range), fn :input, buffer, _ctx, state ->
      assert state.module == FilterA
      assert %Buffer{payload: <<payload>>} = buffer
      out_payload = payload + 1
      state = %{state | state: (state.state || 0) + out_payload}
      {{:ok, buffer: {:output, %Buffer{payload: <<out_payload>>}}}, state}
    end)

    expect(FilterB, :handle_process, Enum.count(test_range), fn :input, buffer, _ctx, state ->
      assert state.module == FilterB
      assert %Buffer{payload: <<payload>>} = buffer
      out_payload = payload * 2
      state = %{state | state: (state.state || 0) + out_payload}
      {{:ok, buffer: {:output, %Buffer{payload: <<out_payload>>}}}, state}
    end)

    assert {{:ok, actions}, %{states: states}} =
             TestedModule.handle_process_list(:input, buffers, %{}, %{states: ctx.states})

    expected_actions =
      test_range
      |> Enum.map(&{:buffer, {:output, %Buffer{payload: <<(&1 + 1) * 2>>}}})

    assert actions == expected_actions

    assert [
             {:a, FilterA, %{module: FilterA, state: state_a}},
             {:b, FilterB, %{module: FilterB, state: state_b}}
           ] = states

    assert state_a == test_range |> Enum.map(&(&1 + 1)) |> Enum.sum()
    assert state_b == test_range |> Enum.map(&((&1 + 1) * 2)) |> Enum.sum()
  end

  test "handle_process with redemands", ctx do
    test_range = 1..10
    buffers = test_range |> Enum.map(&%Buffer{payload: <<&1>>})

    expect(FilterA, :handle_process_list, fn :input, buffers, _ctx, %{module: FilterA} = state ->
      args_list = buffers |> Enum.map(&[:input, &1])
      {{:ok, split: {:handle_process, args_list}}, state}
    end)

    expect(FilterA, :handle_process, Enum.count(test_range), fn :input, buffer, _ctx, state ->
      assert state.module == FilterA
      assert %Buffer{payload: <<payload>>} = buffer
      out_payload = payload + 1
      state = %{state | state: (state.state || 0) + out_payload}

      cond do
        payload < 3 -> {{:ok, redemand: :ouput}, state}
        payload == 3 -> {{:ok, buffer: {:output, %Buffer{payload: <<state.state>>}}}, state}
        payload > 3 -> {{:ok, buffer: {:output, %Buffer{payload: <<out_payload>>}}}, state}
      end
    end)

    expect(FilterB, :handle_process, Enum.count(3..10), fn :input, buffer, _ctx, state ->
      assert state.module == FilterB
      assert %Buffer{payload: <<payload>>} = buffer
      out_payload = payload * 2
      state = %{state | state: (state.state || 0) + out_payload}
      {{:ok, buffer: {:output, %Buffer{payload: <<out_payload>>}}}, state}
    end)

    assert {{:ok, actions}, %{states: states}} =
             TestedModule.handle_process_list(:input, buffers, %{}, %{states: ctx.states})

    accumulated_buffer = {:buffer, {:output, %Buffer{payload: <<(2 + 3 + 4) * 2>>}}}

    regular_actions =
      4..10
      |> Enum.map(&{:buffer, {:output, %Buffer{payload: <<(&1 + 1) * 2>>}}})

    expected_actions = [accumulated_buffer | regular_actions] ++ [redemand: :output]

    assert actions == expected_actions

    assert [
             {:a, FilterA, %{module: FilterA, state: state_a}},
             {:b, FilterB, %{module: FilterB, state: state_b}}
           ] = states

    assert state_a == test_range |> Enum.map(&(&1 + 1)) |> Enum.sum()
    assert state_b == test_range |> Enum.map(&((&1 + 1) * 2)) |> Enum.sum()
  end
end
