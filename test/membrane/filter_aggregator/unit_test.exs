defmodule Membrane.FilterAggregator.UnitTest do
  use ExUnit.Case, async: true

  import Mox

  alias Membrane.Buffer
  alias Membrane.Element.PadData
  alias Membrane.FilterAggregator

  alias Membrane.StreamFormat.Mock, as: MockStreamFormat

  defmodule ElementWithMembranePads do
    @callback membrane_pads() :: [{Membrane.Pad.name(), Membrane.Pad.description()}]
  end

  setup_all do
    behaviours = [
      Membrane.Element.Base,
      Membrane.Element.WithInputPads,
      Membrane.Element.WithOutputPads,
      ElementWithMembranePads
    ]

    defmock(FilterA, for: behaviours)
    defmock(FilterB, for: behaviours)

    stage_opts = %FilterAggregator{
      filters: [
        a: %{__struct__: FilterA},
        b: %{__struct__: FilterB}
      ]
    }

    pad_description_template = %{
      availability: :always,
      stream_format: :any,
      flow_control: :auto,
      demand_unit: :buffers,
      direction: nil,
      name: nil,
      options: nil
    }

    common_pad_data =
      pad_description_template
      |> Map.merge(%{
        stream_format: nil,
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
      playback: :stopped,
      resource_guard: nil,
      utility_supervisor: nil
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
        [
          output: %{pad_description_template | name: :output, direction: :output},
          input: %{pad_description_template | name: :input, direction: :input}
        ]
      end)
    end)
  end

  setup :verify_on_exit!

  test "handle_init with unsupported pad flow control mode", ctx do
    # use stub to get the default value
    pads_descriptions = apply(FilterA, :membrane_pads, [])

    FilterA
    |> expect(:membrane_pads, fn ->
      put_in(pads_descriptions, [:input, :flow_control], :manual)
    end)

    assert_raise RuntimeError, fn -> FilterAggregator.handle_init(%{}, ctx.stage_opts) end
  end

  test "handle_init sets inital states", ctx do
    ctx.filters
    |> Enum.each(fn filter ->
      expect(filter, :handle_init, fn _ctx, %^filter{} -> {[], %{module: filter}} end)
    end)

    assert {[], %{states: result}} =
             FilterAggregator.handle_init(
               %{resource_guard: nil, utility_supervisor: nil},
               ctx.stage_opts
             )

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
      assert pad_data.availability == :always
      assert pad_data.demand == nil
      assert pad_data.direction == pad
      assert pad_data.start_of_stream? == false
      assert pad_data.end_of_stream? == false
      assert pad_data.flow_control in [:auto, :manual]
      assert pad_data.name == pad
      assert pad_data.ref == pad
      # private fields
      assert pad_data.stream_format == nil
    end)
  end

  test "handle_playing with stream format sending", test_ctx do
    expect(FilterA, :handle_playing, fn ctx_a, %{module: FilterA} = state ->
      assert %{
               clock: nil,
               name: :a,
               pads: pads,
               parent_clock: nil,
               playback: :stopped
             } = ctx_a

      assert pads.input == test_ctx.gen_pad_data.(:input)
      assert pads.output == test_ctx.gen_pad_data.(:output)
      assert map_size(pads) == 2

      {[stream_format: {:output, %MockStreamFormat{integer: 1}}], state}
    end)

    expect(FilterB, :handle_stream_format, fn :input,
                                              %MockStreamFormat{integer: 1},
                                              ctx_b,
                                              state ->
      assert state == %{module: FilterB, state: nil}

      assert %{
               clock: nil,
               name: :b,
               old_stream_format: nil,
               pads: pads,
               parent_clock: nil,
               playback: :stopped
             } = ctx_b

      assert pads.input == test_ctx.gen_pad_data.(:input)
      assert pads.output == test_ctx.gen_pad_data.(:output)
      assert map_size(pads) == 2

      {[stream_format: {:output, %MockStreamFormat{integer: 2}}],
       %{state | state: :stream_format_sent}}
    end)

    expect(FilterB, :handle_playing, fn ctx_b, state ->
      # ensure proper callbacks order
      assert state == %{module: FilterB, state: :stream_format_sent}

      assert %{
               clock: nil,
               name: :b,
               pads: pads,
               parent_clock: nil,
               playback: :stopped
             } = ctx_b

      assert pads.input ==
               :input
               |> test_ctx.gen_pad_data.()
               |> Map.put(:stream_format, %MockStreamFormat{integer: 1})

      assert pads.output ==
               :output
               |> test_ctx.gen_pad_data.()
               |> Map.put(:stream_format, %MockStreamFormat{integer: 2})

      assert map_size(pads) == 2

      {[], state}
    end)

    states =
      test_ctx.states
      |> Enum.map(fn {name, module, ctx, state} ->
        {name, module, %{ctx | playback: :stopped}, state}
      end)

    assert {actions, %{states: states}} =
             FilterAggregator.handle_playing(
               %{
                 pads: %{
                   input: %{demand_unit: :buffers, other_name: :output},
                   output: %{demand_unit: :buffers, other_name: :input}
                 }
               },
               %{states: states}
             )

    assert actions == [stream_format: {:output, %MockStreamFormat{integer: 2}}]

    assert [{:a, FilterA, ctx_a, state_a}, {:b, FilterB, ctx_b, state_b}] = states
    assert state_a == %{module: FilterA, state: nil}
    assert state_b == %{module: FilterB, state: :stream_format_sent}

    assert ctx_a.pads.input.stream_format == nil
    assert ctx_a.pads.output.stream_format == %MockStreamFormat{integer: 1}
    assert ctx_b.pads.input.stream_format == %MockStreamFormat{integer: 1}
    assert ctx_b.pads.output.stream_format == %MockStreamFormat{integer: 2}

    assert ctx_a.playback == :playing
    assert ctx_b.playback == :playing
  end

  test "handle_buffers_batch splitting and mapping buffers", ctx do
    test_range = 1..10
    buffers = test_range |> Enum.map(&%Buffer{payload: <<&1>>})
    buffers_count = Enum.count(test_range)

    FilterA
    |> expect(:handle_buffers_batch, fn :input, buffers, %{}, %{module: FilterA} = state ->
      args_list = buffers |> Enum.map(&[:input, &1])
      {[split: {:handle_buffer, args_list}], state}
    end)
    |> expect(:handle_buffer, buffers_count, fn :input, buffer, %{}, state ->
      assert state.module == FilterA
      assert %Buffer{payload: <<payload>>} = buffer
      out_payload = payload + 1
      state = %{state | state: (state.state || 0) + out_payload}
      {[buffer: {:output, %Buffer{payload: <<out_payload>>}}], state}
    end)

    FilterB
    |> expect(:handle_buffers_batch, buffers_count, fn :input, [buffer], %{}, state ->
      assert state.module == FilterB
      assert %Buffer{payload: <<payload>>} = buffer
      out_payload = payload * 2
      state = %{state | state: (state.state || 0) + out_payload}
      {[buffer: {:output, %Buffer{payload: <<out_payload>>}}], state}
    end)

    assert {actions, %{states: states}} =
             FilterAggregator.handle_buffers_batch(:input, buffers, %{}, %{states: ctx.states})

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

    assert ctx_a == ctx.states |> Enum.at(0) |> elem(2)
    assert ctx_b == ctx.states |> Enum.at(1) |> elem(2)
  end

  test "Stream management events & forward action", ctx do
    buffer = %Buffer{payload: "test"}

    FilterA
    |> expect(:handle_start_of_stream, fn :input, %{} = ctx, state ->
      assert ctx.pads.input.start_of_stream? == true
      {[], state}
    end)
    |> expect(:handle_buffers_batch, fn :input, [^buffer], %{} = ctx, state ->
      assert ctx.pads.input.start_of_stream? == true
      {[forward: [buffer]], state}
    end)
    |> expect(:handle_end_of_stream, fn :input, %{} = ctx, state ->
      assert ctx.pads.input.end_of_stream? == true
      {[forward: :end_of_stream], %{state | state: :ok}}
    end)

    FilterB
    |> expect(:handle_start_of_stream, fn :input, %{} = ctx, state ->
      assert ctx.pads.input.start_of_stream? == true
      {[], state}
    end)
    |> expect(:handle_buffers_batch, fn :input, [^buffer], %{} = ctx, state ->
      assert ctx.pads.input.start_of_stream? == true
      {[buffer: {:output, [buffer]}], state}
    end)
    |> expect(:handle_end_of_stream, fn :input, %{} = ctx, state ->
      assert ctx.pads.input.end_of_stream? == true
      {[end_of_stream: :output], %{state | state: :ok}}
    end)

    assert {[], %{states: states}} =
             FilterAggregator.handle_start_of_stream(:input, %{}, %{
               states: ctx.states
             })

    assert {[buffer: {:output, buffers}], %{states: states}} =
             FilterAggregator.handle_buffers_batch(:input, [buffer], %{}, %{states: states})

    assert List.wrap(buffers) == [buffer]

    assert {[end_of_stream: :output], %{states: states}} =
             FilterAggregator.handle_end_of_stream(:input, %{}, %{states: states})

    assert [
             {:a, FilterA, ctx_a, %{module: FilterA, state: :ok}},
             {:b, FilterB, ctx_b, %{module: FilterB, state: :ok}}
           ] = states

    assert ctx_a.pads.output.end_of_stream? == true
    assert ctx_b.pads.output.end_of_stream? == true
  end

  test "Custom events send & forward", ctx do
    alias Membrane.Event.Discontinuity
    event = %Discontinuity{}

    FilterA
    |> expect(:handle_event, fn :input, ^event, %{}, state ->
      {[forward: event], %{state | state: :ok}}
    end)

    FilterB
    |> expect(:handle_event, fn :input, ^event, %{}, state ->
      {[event: {:output, event}], %{state | state: :ok}}
    end)

    assert {[event: {:output, ^event}], %{states: states}} =
             FilterAggregator.handle_event(:input, event, %{}, %{states: ctx.states})

    assert [
             {:a, FilterA, _ctx_a, %{module: FilterA, state: :ok}},
             {:b, FilterB, _ctx_b, %{module: FilterB, state: :ok}}
           ] = states
  end
end
