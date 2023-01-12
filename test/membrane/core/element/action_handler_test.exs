defmodule Membrane.Core.Element.ActionHandlerTest do
  use ExUnit.Case, async: true

  alias Membrane.{ActionError, Buffer, ElementError, PadDirectionError}
  alias Membrane.Core.Element.State
  alias Membrane.Support.DemandsTest.Filter
  alias Membrane.Support.Element.{TrivialFilter, TrivialSource}

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Core.Message, as: Message

  @module Membrane.Core.Element.ActionHandler
  @mock_stream_format %Membrane.StreamFormat.Mock{integer: 42}
  defp demand_test_filter(_context) do
    state =
      struct(State,
        module: Filter,
        name: :test_name,
        type: :filter,
        playback: :stopped,
        synchronization: %{clock: nil, parent_clock: nil},
        delayed_demands: MapSet.new(),
        pads_data: %{
          input:
            struct(Membrane.Element.PadData,
              direction: :input,
              pid: self(),
              flow_control: :manual,
              demand: 0
            ),
          input_push:
            struct(Membrane.Element.PadData,
              direction: :input,
              pid: self(),
              flow_control: :push
            )
        }
      )

    [state: state]
  end

  describe "handling demand action" do
    setup :demand_test_filter

    test "delaying demand", %{state: state} do
      state = %{state | playback: :playing, supplying_demand?: true}
      state = @module.handle_action({:demand, {:input, 10}}, :handle_info, %{}, state)
      assert state.pads_data.input.demand == 10
      assert MapSet.new([{:input, :supply}]) == state.delayed_demands
    end

    test "returning error on invalid constraints", %{state: state} do
      assert_raise ActionError, ~r/stopped/, fn ->
        @module.handle_action({:demand, {:input, 10}}, :handle_info, %{}, state)
      end

      state = %{state | playback: :playing}

      assert_raise ElementError, ~r/pad :input_push.*push mode/, fn ->
        @module.handle_action({:demand, {:input_push, 10}}, :handle_info, %{}, state)
      end
    end
  end

  defp trivial_filter_state(_context) do
    state =
      struct(State,
        module: TrivialFilter,
        name: :elem_name,
        type: :filter,
        synchronization: %{clock: nil, parent_clock: nil},
        delayed_demands: MapSet.new(),
        playback: :stopped,
        pads_data: %{
          output: %{
            direction: :output,
            pid: self(),
            other_ref: :other_ref,
            stream_format: nil,
            other_demand_unit: :bytes,
            start_of_stream?: true,
            end_of_stream?: false,
            flow_control: :push
          },
          input: %{
            direction: :input,
            pid: self(),
            other_ref: :other_input,
            stream_format: nil,
            start_of_stream?: true,
            end_of_stream?: false,
            flow_control: :push
          }
        }
      )

    [state: state]
  end

  @mock_buffer %Buffer{payload: "Hello"}
  defp buffer_action(pad), do: {:buffer, {pad, @mock_buffer}}

  describe "handling :buffer action" do
    setup :trivial_filter_state

    test "when element is stopped", %{state: state} do
      assert_raise ActionError, ~r/stopped/, fn ->
        @module.handle_action(
          buffer_action(:output),
          :handle_info,
          %{},
          state
        )
      end
    end

    test "when element is stopped and not moving to playing", %{state: state} do
      assert_raise ActionError, ~r/stopped/, fn ->
        @module.handle_action(
          buffer_action(:output),
          :handle_info,
          %{},
          state
        )
      end
    end

    test "when element is moving to playing", %{state: state} do
      state =
        %{state | playback: :playing}
        |> PadModel.set_data!(:output, :stream_format, @mock_stream_format)

      result =
        @module.handle_action(
          buffer_action(:output),
          :handle_playing,
          %{},
          state
        )

      assert result == state
      assert_received Message.new(:buffer, [@mock_buffer], for_pad: :other_ref)
    end

    test "when element is playing", %{state: state} do
      state =
        %{state | playback: :playing}
        |> PadModel.set_data!(:output, :stream_format, @mock_stream_format)

      result =
        @module.handle_action(
          buffer_action(:output),
          :handle_info,
          %{},
          state
        )

      assert result == state
      assert_received Message.new(:buffer, [@mock_buffer], for_pad: :other_ref)
    end

    test "when pad doesn't exist in the element", %{state: state} do
      state = %{state | playback: :playing}

      assert_raise MatchError, ~r/:unknown_pad/i, fn ->
        @module.handle_action(
          buffer_action(:invalid_pad_ref),
          :handle_info,
          %{},
          state
        )
      end
    end

    test "when eos has already been sent", %{state: state} do
      state =
        %{state | playback: :playing}
        |> PadModel.set_data!(:output, :end_of_stream?, true)
        |> PadModel.set_data!(:output, :stream_format, @mock_stream_format)

      assert_raise ElementError, ~r/:output.*end ?of ?stream.*sent/i, fn ->
        @module.handle_action(
          buffer_action(:output),
          :handle_info,
          %{},
          state
        )
      end
    end

    test "with invalid buffer(s)", %{state: state} do
      state =
        %{state | playback: :playing}
        |> PadModel.set_data!(:output, :stream_format, @mock_stream_format)

      assert_raise ElementError, ~r/invalid buffer.*:not_a_buffer/i, fn ->
        @module.handle_action(
          {:buffer, {:output, :not_a_buffer}},
          :handle_info,
          %{},
          state
        )
      end

      refute_received Message.new(:buffer, [_, :other_ref])

      assert_raise ElementError, ~r/invalid buffer.*:not_a_buffer/i, fn ->
        @module.handle_action(
          {:buffer, {:output, [@mock_buffer, :not_a_buffer]}},
          :handle_info,
          %{},
          state
        )
      end

      refute_received Message.new(:buffer, [_, :other_ref])
    end

    test "with empty buffer list", %{state: state} do
      state =
        %{state | playback: :playing}
        |> PadModel.set_data!(:output, :stream_format, @mock_stream_format)

      result =
        @module.handle_action(
          {:buffer, {:output, []}},
          :handle_info,
          %{},
          state
        )

      assert result == state
      refute_received Message.new(:buffer, [_, :other_ref])
    end

    test "if action handler raises exception when stream format is not sent before the first buffer",
         %{
           state: state
         } do
      state = %{state | playback: :playing}

      assert_raise(ElementError, ~r/buffer.*stream.*format.*not.*sent/, fn ->
        @module.handle_action(
          {:buffer, {:output, %Membrane.Buffer{payload: "test"}}},
          :handle_demand,
          %{},
          state
        )
      end)
    end
  end

  @mock_event %Membrane.Core.Events.EndOfStream{}
  defp event_action(pad), do: {:event, {pad, @mock_event}}

  describe "handling :event action" do
    setup :trivial_filter_state

    test "when element is stopped", %{state: state} do
      assert_raise ActionError, ~r/stopped/, fn ->
        @module.handle_action(
          event_action(:output),
          :handle_info,
          %{},
          state
        )
      end
    end

    test "when element is playing and event is EndOfStream", %{state: state} do
      state = %{state | playback: :playing}

      result =
        @module.handle_action(
          event_action(:output),
          :handle_info,
          %{},
          state
        )

      assert result == PadModel.set_data!(state, :output, :end_of_stream?, true)
      assert_received Message.new(:event, @mock_event, for_pad: :other_ref)
    end

    test "when pad doesn't exist in the element", %{state: state} do
      state = %{state | playback: :playing}

      assert_raise MatchError, ~r/:unknown_pad/i, fn ->
        @module.handle_action(
          event_action(:invalid_pad_ref),
          :handle_info,
          %{},
          state
        )
      end
    end

    test "with invalid event", %{state: state} do
      state = %{state | playback: :playing}

      assert_raise ElementError, ~r/invalid event.*:not_an_event/i, fn ->
        @module.handle_action(
          {:event, {:output, :not_an_event}},
          :handle_info,
          %{},
          state
        )
      end
    end

    test "when eos has already been sent", %{state: state} do
      state =
        %{state | playback: :playing}
        |> PadModel.set_data!(:output, :end_of_stream?, true)

      assert_raise ElementError, ~r/end ?of ?stream.*set.*:output/i, fn ->
        @module.handle_action(
          event_action(:output),
          :handle_info,
          %{},
          state
        )
      end
    end

    test "invalid pad direction", %{state: state} do
      state = %{state | playback: :playing}

      assert_raise PadDirectionError, ~r/:input/, fn ->
        @module.handle_action(
          event_action(:input),
          :handle_info,
          %{},
          state
        )
      end
    end
  end

  defp stream_format_action(pad), do: {:stream_format, {pad, @mock_stream_format}}

  describe "handling :stream_format action" do
    setup :trivial_filter_state

    test "when element is stopped", %{state: state} do
      assert_raise ActionError, ~r/stopped/, fn ->
        @module.handle_action(
          stream_format_action(:output),
          :handle_info,
          %{},
          state
        )
      end
    end

    test "when pad doesn't exist in the element", %{state: state} do
      state = %{state | playback: :playing}

      assert_raise MatchError, ~r/:unknown_pad/i, fn ->
        @module.handle_action(
          stream_format_action(:invalid_pad_ref),
          :handle_info,
          %{},
          state
        )
      end
    end

    test "invalid pad direction", %{state: state} do
      state = %{state | playback: :playing}

      assert_raise PadDirectionError, ~r/:input/, fn ->
        @module.handle_action(
          stream_format_action(:input),
          :handle_info,
          %{},
          state
        )
      end

      refute_received Message.new(:stream_format, @mock_stream_format, for_pad: :other_ref)
    end
  end

  @mock_notification :hello_test

  describe "handling :child_notification action" do
    setup :trivial_filter_state

    test "when parent pid is set", %{state: state} do
      state = %{state | parent_pid: self()}

      result =
        @module.handle_action(
          {:notify_parent, @mock_notification},
          :handle_other,
          %{},
          state
        )

      assert result == state
      assert_received Message.new(:child_notification, [:elem_name, @mock_notification])
    end
  end

  describe "handling :redemand action" do
    setup :trivial_filter_state

    test "when element is stopped", %{state: state} do
      assert_raise ActionError, ~r/stopped/, fn ->
        @module.handle_action(
          {:redemand, :output},
          :handle_info,
          %{},
          state
        )
      end
    end

    test "when pad doesn't exist in the element", %{state: state} do
      state = %{state | playback: :playing}

      assert_raise MatchError, ~r/:unknown_pad/i, fn ->
        @module.handle_action(
          {:redemand, :invalid_pad_ref},
          :handle_info,
          %{},
          state
        )
      end
    end

    test "when pad works in push mode", %{state: state} do
      state = %{state | playback: :playing}

      assert_raise ElementError, ~r/pad :output.*push mode/i, fn ->
        @module.handle_action(
          {:redemand, :output},
          :handle_info,
          %{},
          state
        )
      end
    end

    test "when pad works in pull mode", %{state: state} do
      state =
        %{state | supplying_demand?: true, playback: :playing}
        |> PadModel.set_data!(:output, :flow_control, :manual)

      new_state =
        @module.handle_action(
          {:redemand, :output},
          :handle_info,
          %{},
          state
        )

      assert %{new_state | delayed_demands: MapSet.new()} == state
      assert MapSet.member?(new_state.delayed_demands, {:output, :redemand}) == true
    end
  end

  defp playing_trivial_source(_context) do
    state =
      struct(State,
        module: TrivialSource,
        name: :elem_name,
        synchronization: %{clock: nil, parent_clock: nil},
        type: :source,
        pads_data: %{
          output: %{
            direction: :output,
            pid: self(),
            flow_control: :manual,
            demand: 0
          }
        },
        playback: :playing
      )

    [state: state]
  end

  describe "handling_actions" do
    setup :playing_trivial_source

    test "when all :redemand actions are at the end", %{state: state} do
      Enum.each(
        [
          [notify: :a, notify: :b, redemand: :output],
          [notify: :a, notify: :b, redemand: :output, redemand: :output],
          [notify: :a, notify: :b]
        ],
        fn actions ->
          assert {actions, state} == @module.transform_actions(actions, :handle_info, %{}, state)
        end
      )
    end

    test "when :redemand is not the last action", %{state: state} do
      assert_raise ActionError, ~r/redemand.*last/i, fn ->
        @module.transform_actions(
          [redemand: :output, notify_parent: :a, notify_parent: :b],
          :handle_other,
          %{},
          state
        )
      end
    end
  end
end
