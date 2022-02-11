defmodule Membrane.FilterAggregatorTest do
  use ExUnit.Case, async: true

  import Mox

  alias Membrane.Buffer
  alias Membrane.Caps.Mock, as: MockCaps
  alias Membrane.FilterAggregator, as: TestedModule
  alias Membrane.Element.PadData

  alias Membrane.Element.CallbackContext.{
    Caps,
    Demand,
    Event,
    Other,
    PlaybackChange,
    Process,
    StreamManagement
  }

  @moduletag :focus

  setup_all do
    behaviours = [
      Membrane.Filter,
      Membrane.Element.Base,
      Membrane.Element.WithInputPads,
      Membrane.Element.WithOutputPads
    ]

    defmock(FilterA, for: behaviours)
    defmock(FilterB, for: behaviours)

    stage_opts = %TestedModule{
      filters: [
        a: %{__struct__: FilterA},
        b: %{__struct__: FilterB}
      ]
    }

    pad_description_template = %{
      availability: :always,
      caps: :any,
      demand_mode: :manual,
      demand_unit: :buffers,
      direction: nil,
      mode: :pull,
      name: nil,
      options: nil
    }

    common_pad_data =
      pad_description_template
      |> Map.merge(%{
        accepted_caps: :any,
        caps: nil,
        demand: 0,
        ref: nil,
        other_ref: nil,
        other_demand_unit: :buffers,
        pid: nil
      })
      |> then(&struct!(PadData, &1))

    common_context = %{
      pads: %{
        output: %{
          common_pad_data
          | name: :output,
            direction: :output,
            ref: :output,
            other_ref: :input
        },
        input: %{
          common_pad_data
          | name: :input,
            direction: :input,
            ref: :input,
            other_ref: :output
        }
      },
      clock: nil,
      name: nil,
      parent_clock: nil,
      playback_state: :stopped
    }

    states = [
      {:a, FilterA, %{common_context | name: :a}, %{module: FilterA, state: nil}},
      {:b, FilterB, %{common_context | name: :b}, %{module: FilterB, state: nil}}
    ]

    [
      filters: [FilterA, FilterB],
      stage_opts: stage_opts,
      states: states,
      pad_description_template: pad_description_template,
      gen_pad_data: fn pad_name ->
        other_ref =
          case pad_name do
            :input -> :output
            :output -> :input
          end

        common_pad_data
        |> Map.merge(%{direction: pad_name, name: pad_name, ref: pad_name, other_ref: other_ref})
      end
    ]
  end

  setup %{filters: filters, pad_description_template: pad_description_template} do
    filters
    |> Enum.each(fn filter ->
      stub(filter, :__struct__, fn kv -> kv |> Map.new() |> Map.put(:__struct__, filter) end)

      stub(filter, :membrane_pads, fn ->
        %{
          output: %{pad_description_template | name: :output, direction: :output},
          input: %{pad_description_template | name: :input, direction: :input}
        }
      end)
    end)
  end

  setup :verify_on_exit!

  test "handle_init sets inital states", ctx do
    ctx.filters
    |> Enum.each(fn filter ->
      expect(filter, :handle_init, fn %^filter{} -> {:ok, %{module: filter}} end)
    end)

    assert {:ok, %{states: result}} = TestedModule.handle_init(ctx.stage_opts)

    assert [{:a, FilterA, ctx_a, state_a}, {:b, FilterB, ctx_b, state_b}] = result
    assert state_a == %{module: FilterA}
    assert state_b == %{module: FilterB}

    assert ctx_a.pads
           |> Map.keys()
           |> MapSet.new()
           |> MapSet.equal?(MapSet.new([:input, :output]))

    assert ctx_b.pads
           |> Map.keys()
           |> MapSet.new()
           |> MapSet.equal?(MapSet.new([:input, :output]))

    # Check public `Membrane.Element.PadData` fields
    [ctx_a, ctx_b]
    |> Enum.flat_map(& &1.pads)
    |> Enum.each(fn {pad, pad_data} ->
      assert pad_data.accepted_caps == :any
      assert pad_data.availability == :always
      assert pad_data.demand == 0
      assert pad_data.direction == pad
      assert pad_data.start_of_stream? == false
      assert pad_data.end_of_stream? == false
      assert pad_data.mode == :pull
      assert pad_data.name == pad
      assert pad_data.ref == pad
      # private fields
      assert pad_data.caps == nil
    end)
  end

  test "handle_prepared_to_playing with caps sending", test_ctx do
    expect(FilterA, :handle_prepared_to_playing, fn ctx_a, %{module: FilterA} = state ->
      assert %PlaybackChange{
               clock: nil,
               name: :a,
               pads: pads,
               parent_clock: nil,
               playback_state: :prepared
             } = ctx_a

      assert pads.input == test_ctx.gen_pad_data.(:input)
      assert pads.output == test_ctx.gen_pad_data.(:output)
      assert map_size(pads) == 2

      {{:ok, caps: {:output, %MockCaps{integer: 1}}}, state}
    end)

    expect(FilterB, :handle_caps, fn :input, %MockCaps{integer: 1}, ctx_b, state ->
      assert state == %{module: FilterB, state: nil}

      assert %Caps{
               clock: nil,
               name: :b,
               old_caps: nil,
               pads: pads,
               parent_clock: nil,
               playback_state: :prepared
             } = ctx_b

      assert pads.input == test_ctx.gen_pad_data.(:input)
      assert pads.output == test_ctx.gen_pad_data.(:output)
      assert map_size(pads) == 2

      {{:ok, caps: {:output, %MockCaps{integer: 2}}}, %{state | state: :caps_sent}}
    end)

    expect(FilterB, :handle_prepared_to_playing, fn ctx_b, state ->
      # ensure proper callbacks order
      assert state == %{module: FilterB, state: :caps_sent}

      assert %PlaybackChange{
               clock: nil,
               name: :b,
               pads: pads,
               parent_clock: nil,
               playback_state: :prepared
             } = ctx_b

      assert pads.input ==
               :input |> test_ctx.gen_pad_data.() |> Map.put(:caps, %MockCaps{integer: 1})

      assert pads.output ==
               :output |> test_ctx.gen_pad_data.() |> Map.put(:caps, %MockCaps{integer: 2})

      assert map_size(pads) == 2

      {:ok, state}
    end)

    states =
      test_ctx.states
      |> Enum.map(fn {name, module, ctx, state} ->
        {name, module, %{ctx | playback_state: :prepared}, state}
      end)

    assert {{:ok, actions}, %{states: states}} =
             TestedModule.handle_prepared_to_playing(%{}, %{states: states})

    assert actions == [caps: {:output, %MockCaps{integer: 2}}]

    assert [{:a, FilterA, ctx_a, state_a}, {:b, FilterB, ctx_b, state_b}] = states
    assert state_a == %{module: FilterA, state: nil}
    assert state_b == %{module: FilterB, state: :caps_sent}

    assert ctx_a.pads.input.caps == nil
    assert ctx_a.pads.output.caps == %MockCaps{integer: 1}
    assert ctx_b.pads.input.caps == %MockCaps{integer: 1}
    assert ctx_b.pads.output.caps == %MockCaps{integer: 2}

    assert ctx_a.playback_state == :playing
    assert ctx_b.playback_state == :playing
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
             {:a, FilterA, ctx_a, %{module: FilterA, state: state_a}},
             {:b, FilterB, ctx_b, %{module: FilterB, state: state_b}}
           ] = states

    assert state_a == test_range |> Enum.map(&(&1 + 1)) |> Enum.sum()
    assert state_b == test_range |> Enum.map(&((&1 + 1) * 2)) |> Enum.sum()

    assert ctx_a.pads.input.demand == -10
    assert ctx_a.pads.output.demand == -10
    assert ctx_b.pads.input.demand == -10
    assert ctx_b.pads.output.demand == -10
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

      # Accumulate 3 first, modified buffers, send as one using accumulated state, the rest pass with modified payload
      cond do
        payload < 3 -> {{:ok, redemand: :output}, state}
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
             {:a, FilterA, ctx_a, %{module: FilterA, state: state_a}},
             {:b, FilterB, ctx_b, %{module: FilterB, state: state_b}}
           ] = states

    assert state_a == test_range |> Enum.map(&(&1 + 1)) |> Enum.sum()
    assert state_b == test_range |> Enum.map(&((&1 + 1) * 2)) |> Enum.sum()
  end

  test "handle_demand", ctx do
    incoming_demand = 10

    expect(FilterB, :handle_demand, fn :output, demand, :buffers, _ctx, state ->
      assert state.module == FilterB
      assert demand == incoming_demand
      out_demand = demand * 2
      state = %{state | state: "B"}
      {{:ok, demand: {:input, out_demand}}, state}
    end)

    expect(FilterA, :handle_demand, fn :output, demand, :buffers, _ctx, state ->
      assert state.module == FilterA
      out_demand = demand + 1
      state = %{state | state: "A"}
      {{:ok, demand: {:input, out_demand}}, state}
    end)

    assert {{:ok, actions}, %{states: states}} =
             TestedModule.handle_demand(:output, incoming_demand, :buffers, %{}, %{
               states: ctx.states
             })

    assert actions == [demand: {:input, incoming_demand * 2 + 1}]
    assert [{:a, FilterA, ctx_a, state_a}, {:b, FilterB, ctx_b, state_b}] = states
    assert state_a == %{module: FilterA, state: "A"}
    assert state_b == %{module: FilterB, state: "B"}
    assert ctx_b.pads.output.demand == incoming_demand
    assert ctx_b.pads.input.demand == incoming_demand * 2
    assert ctx_a.pads.output.demand == incoming_demand * 2
    assert ctx_a.pads.input.demand == incoming_demand * 2 + 1
  end
end
