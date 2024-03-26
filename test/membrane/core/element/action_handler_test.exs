defmodule Membrane.Core.Element.ActionHandlerTest do
  use ExUnit.Case, async: true

  alias Membrane.{ActionError, Buffer, ElementError, PadDirectionError}
  alias Membrane.Core.Element.{AtomicDemand, State}
  alias Membrane.Core.SubprocessSupervisor
  alias Membrane.Support.DemandsTest.Filter
  alias Membrane.Support.Element.{TrivialFilter, TrivialSource}

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Core.Message, as: Message

  @module Membrane.Core.Element.ActionHandler
  @mock_stream_format %Membrane.StreamFormat.Mock{integer: 42}
  @unknown_pad_error_module if Version.match?(System.version(), ">= 1.14.0-dev"),
                              do: Membrane.UnknownPadError,
                              else: MatchError

  defp demand_test_filter(_context) do
    state =
      struct!(State,
        module: Filter,
        name: :test_name,
        type: :filter,
        playback: :stopped,
        synchronization: %{clock: nil, parent_clock: nil},
        delayed_demands: MapSet.new(),
        # handling_action?: false,
        pads_to_snapshot: MapSet.new(),
        pads_data: %{
          input:
            struct(Membrane.Element.PadData,
              direction: :input,
              pid: self(),
              flow_control: :manual,
              demand: 0,
              total_buffers_metric: :atomics.new(1, [])
            ),
          input_push:
            struct(Membrane.Element.PadData,
              direction: :input,
              pid: self(),
              flow_control: :push,
              total_buffers_metric: :atomics.new(1, [])
            )
        },
        pads_info: %{
          input: %{flow_control: :manual},
          input_push: %{flow_control: :push}
        },
        satisfied_auto_output_pads: MapSet.new(),
        awaiting_auto_input_pads: MapSet.new(),
        popping_auto_flow_queue?: false
      )

    [state: state]
  end

  describe "handling demand action" do
    setup :demand_test_filter

    test "delaying demand", %{state: state} do
      state = %{state | playback: :playing, delay_demands?: true}
      state = @module.handle_action({:demand, {:input, 10}}, :handle_info, %{}, state)
      assert state.pads_data.input.manual_demand_size == 10
      assert MapSet.new([{:input, :supply}]) == state.delayed_demands
    end

    test "returning error on invalid constraints", %{state: state} do
      assert_raise ActionError, ~r/stopped/, fn ->
        @module.handle_action({:demand, {:input, 10}}, :handle_info, %{}, state)
      end

      state = %{state | playback: :playing}

      assert_raise ElementError, ~r/pad :input_push.*push flow control/, fn ->
        @module.handle_action({:demand, {:input_push, 10}}, :handle_info, %{}, state)
      end
    end
  end

  defp trivial_filter_state(_context) do
    supervisor = SubprocessSupervisor.start_link!()

    input_atomic_demand =
      AtomicDemand.new(%{
        receiver_effective_flow_control: :push,
        receiver_process: self(),
        receiver_demand_unit: :buffers,
        sender_process: spawn(fn -> :ok end),
        sender_pad_ref: :output,
        supervisor: supervisor
      })

    output_atomic_demand =
      AtomicDemand.new(%{
        receiver_effective_flow_control: :push,
        receiver_process: spawn(fn -> :ok end),
        receiver_demand_unit: :bytes,
        sender_process: self(),
        sender_pad_ref: :output,
        supervisor: supervisor
      })

    state =
      struct!(State,
        module: TrivialFilter,
        name: :elem_name,
        type: :filter,
        synchronization: %{clock: nil, parent_clock: nil},
        delayed_demands: MapSet.new(),
        playback: :stopped,
        # handling_action?: false,
        pads_to_snapshot: MapSet.new(),
        pads_data: %{
          output: %{
            direction: :output,
            pid: self(),
            other_ref: :other_ref,
            stream_format: nil,
            demand_unit: :bytes,
            other_demand_unit: :bytes,
            start_of_stream?: true,
            end_of_stream?: false,
            flow_control: :push,
            atomic_demand: output_atomic_demand,
            demand: 0,
            stalker_metrics: %{total_buffers: :atomics.new(1, [])}
          },
          input: %{
            direction: :input,
            pid: self(),
            other_ref: :other_input,
            stream_format: nil,
            start_of_stream?: true,
            end_of_stream?: false,
            flow_control: :push,
            atomic_demand: input_atomic_demand,
            demand: 0,
            stalker_metrics: %{total_buffers: :atomics.new(1, [])}
          }
        },
        pads_info: %{
          output: %{flow_control: :push},
          input: %{flow_control: :push}
        },
        satisfied_auto_output_pads: MapSet.new(),
        awaiting_auto_input_pads: MapSet.new(),
        popping_auto_flow_queue?: false
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

      assert result.pads_data.output.demand < 0
      assert result.pads_to_snapshot == MapSet.new([:output])
      assert AtomicDemand.get(result.pads_data.output.atomic_demand) < 0

      assert put_in(result, [:pads_data, :output, :demand], 0)
             |> Map.put(:pads_to_snapshot, MapSet.new()) == state

      assert_received Message.new(:buffer, [@mock_buffer], for_pad: :other_ref)
    end

    test "when pad doesn't exist in the element", %{state: state} do
      state = %{state | playback: :playing}

      assert_raise @unknown_pad_error_module, ~r/unknown.*pad/i, fn ->
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

      assert_raise @unknown_pad_error_module, ~r/unknown.*pad/i, fn ->
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

      assert_raise @unknown_pad_error_module, ~r/unknown.*pad/i, fn ->
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

      assert_raise @unknown_pad_error_module, ~r/unknown.*pad/i, fn ->
        @module.handle_action(
          {:redemand, :invalid_pad_ref},
          :handle_info,
          %{},
          state
        )
      end
    end

    test "when pad works in push flow control mode", %{state: state} do
      state = %{state | playback: :playing}

      assert_raise ElementError, ~r/pad :output.*push flow control/i, fn ->
        @module.handle_action(
          {:redemand, :output},
          :handle_info,
          %{},
          state
        )
      end
    end

    test "when pad works in auto or manual flow control mode", %{state: state} do
      state =
        %{state | delay_demands?: true, playback: :playing}
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
        # handling_action?: false,
        pads_to_snapshot: MapSet.new(),
        pads_data: %{
          output: %{
            direction: :output,
            pid: self(),
            flow_control: :manual,
            demand: 0
          }
        },
        pads_info: %{
          output: %{flow_control: :manual}
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
  end
end
