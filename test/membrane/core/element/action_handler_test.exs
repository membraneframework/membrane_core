defmodule Membrane.Core.Element.ActionHandlerTest do
  use ExUnit.Case, async: true

  alias Membrane.{ActionError, Buffer}
  alias Membrane.Core.{Message, Playback}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.State
  alias Membrane.Support.DemandsTest.Filter
  alias Membrane.Support.Element.{TrivialFilter, TrivialSource}

  require Message

  @module Membrane.Core.Element.ActionHandler

  defp demand_test_filter(_context) do
    state = %{
      State.new(%{module: Filter, name: :test_name, parent_clock: nil, sync: nil, parent: self()})
      | type: :filter,
        pads: %{
          data: %{
            input:
              struct(Membrane.Element.PadData,
                direction: :input,
                pid: self(),
                mode: :pull,
                demand_mode: :manual,
                demand: 0
              ),
            input_push:
              struct(Membrane.Element.PadData,
                direction: :input,
                pid: self(),
                mode: :push
              )
          }
        }
    }

    [state: state]
  end

  describe "handling demand action" do
    setup :demand_test_filter

    test "delaying demand", %{state: state} do
      [{:playing, :handle_other}, {:prepared, :handle_prepared_to_playing}]
      |> Enum.each(fn {playback, callback} ->
        state = %{state | playback: %Playback{state: playback}, supplying_demand?: true}
        assert {:ok, state} = @module.handle_action({:demand, {:input, 10}}, callback, %{}, state)
        assert state.pads.data.input.demand == 10
        assert MapSet.new([{:input, :supply}]) == state.delayed_demands
      end)

      state = %{state | playback: %Playback{state: :playing}}

      assert {:ok, state} =
               @module.handle_action(
                 {:demand, {:input, 10}},
                 :handle_other,
                 %{},
                 %{state | supplying_demand?: true}
               )

      assert state.pads.data.input.demand == 10
      assert MapSet.new([{:input, :supply}]) == state.delayed_demands
    end

    test "returning error on invalid constraints", %{state: state} do
      state = state |> set_playback_state(:prepared)

      assert_raise ActionError, ~r/prepared/, fn ->
        @module.handle_action({:demand, {:input, 10}}, :handle_other, %{}, state)
      end

      state = state |> set_playback_state(:playing)

      assert_raise ActionError, ~r/pad :input_push.*:push mode/, fn ->
        @module.handle_action({:demand, {:input_push, 10}}, :handle_other, %{}, state)
      end
    end
  end

  defp trivial_filter_state(_context) do
    state = %{
      State.new(%{
        module: TrivialFilter,
        name: :elem_name,
        parent_clock: nil,
        sync: nil,
        parent: nil
      })
      | type: :filter,
        pads: %{
          data: %{
            output: %{
              direction: :output,
              pid: self(),
              other_ref: :other_ref,
              caps: nil,
              other_demand_unit: :bytes,
              start_of_stream?: true,
              end_of_stream?: false,
              mode: :push,
              accepted_caps: :any
            },
            input: %{
              direction: :input,
              pid: self(),
              other_ref: :other_input,
              caps: nil,
              start_of_stream?: true,
              end_of_stream?: false,
              mode: :push,
              accepted_caps: :any
            }
          }
        }
    }

    [state: state]
  end

  defp set_playback_state(element_state, pb_state) do
    element_state |> Bunch.Struct.put_in([:playback, :state], pb_state)
  end

  @mock_buffer %Buffer{payload: "Hello"}
  defp buffer_action(pad), do: {:buffer, {pad, @mock_buffer}}

  describe "handling :buffer action" do
    setup :trivial_filter_state

    test "when element is stopped", %{state: state} do
      assert_raise ActionError, ~r/stopped/, fn ->
        @module.handle_action(
          buffer_action(:output),
          :handle_other,
          %{},
          state
        )
      end
    end

    test "swhen element is prepared and not moving to playing", %{state: state} do
      state = state |> set_playback_state(:prepared)

      assert_raise ActionError, ~r/prepared/, fn ->
        @module.handle_action(
          buffer_action(:output),
          :handle_other,
          %{},
          state
        )
      end
    end

    test "when element is moving to playing", %{state: state} do
      state = state |> set_playback_state(:prepared) |> PadModel.set_data!(:output, :caps, :any)

      result =
        @module.handle_action(
          buffer_action(:output),
          :handle_prepared_to_playing,
          %{},
          state
        )

      assert result == {:ok, state}
      assert_received Message.new(:buffer, [@mock_buffer], for_pad: :other_ref)
    end

    test "when element is playing", %{state: state} do
      state = state |> set_playback_state(:playing) |> PadModel.set_data!(:output, :caps, :any)

      result =
        @module.handle_action(
          buffer_action(:output),
          :handle_other,
          %{},
          state
        )

      assert result == {:ok, state}
      assert_received Message.new(:buffer, [@mock_buffer], for_pad: :other_ref)
    end

    test "when pad doesn't exist in the element", %{state: state} do
      state = state |> set_playback_state(:playing)

      assert_raise ActionError, ~r/pad :invalid_pad_ref/i, fn ->
        @module.handle_action(
          buffer_action(:invalid_pad_ref),
          :handle_other,
          %{},
          state
        )
      end
    end

    test "when eos has already been sent", %{state: state} do
      state =
        state
        |> set_playback_state(:playing)
        |> PadModel.set_data!(:output, :end_of_stream?, true)
        |> PadModel.set_data!(:output, :caps, :any)

      assert_raise ActionError, ~r/end ?of ?stream.*sent.*:output/i, fn ->
        @module.handle_action(
          buffer_action(:output),
          :handle_other,
          %{},
          state
        )
      end
    end

    test "with invalid buffer(s)", %{state: state} do
      state = state |> set_playback_state(:playing) |> PadModel.set_data!(:output, :caps, :any)

      assert_raise ActionError, ~r/invalid buffer.*:not_a_buffer/i, fn ->
        @module.handle_action(
          {:buffer, {:output, :not_a_buffer}},
          :handle_other,
          %{},
          state
        )
      end

      refute_received Message.new(:buffer, [_, :other_ref])

      assert_raise ActionError, ~r/invalid buffer.*:not_a_buffer/i, fn ->
        @module.handle_action(
          {:buffer, {:output, [@mock_buffer, :not_a_buffer]}},
          :handle_other,
          %{},
          state
        )
      end

      refute_received Message.new(:buffer, [_, :other_ref])
    end

    test "with empty buffer list", %{state: state} do
      state = state |> set_playback_state(:playing) |> PadModel.set_data!(:output, :caps, :any)

      result =
        @module.handle_action(
          {:buffer, {:output, []}},
          :handle_other,
          %{},
          state
        )

      assert result == {:ok, state}
      refute_received Message.new(:buffer, [_, :other_ref])
    end

    test "if action handler raises exception when caps are sent before the first buffer", %{
      state: state
    } do
      state = state |> set_playback_state(:playing)

      assert_raise(
        ActionError,
        ~r/Caps were not sent on this pad before the first buffer was/,
        fn ->
          @module.handle_action(
            {:buffer, {:output, %Membrane.Buffer{payload: "test"}}},
            :handle_demand,
            %{},
            state
          )
        end
      )
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
          :handle_other,
          %{},
          state
        )
      end
    end

    test "when element is playing and event is EndOfStream", %{state: state} do
      state = state |> set_playback_state(:playing)

      result =
        @module.handle_action(
          event_action(:output),
          :handle_other,
          %{},
          state
        )

      assert result == {:ok, state |> PadModel.set_data!(:output, :end_of_stream?, true)}
      assert_received Message.new(:event, @mock_event, for_pad: :other_ref)
    end

    test "when pad doesn't exist in the element", %{state: state} do
      state = state |> set_playback_state(:playing)

      assert_raise ActionError, ~r/pad :invalid_pad_ref/i, fn ->
        @module.handle_action(
          event_action(:invalid_pad_ref),
          :handle_other,
          %{},
          state
        )
      end
    end

    test "with invalid event", %{state: state} do
      state = state |> set_playback_state(:playing)

      assert_raise ActionError, ~r/invalid event.*:not_an_event/i, fn ->
        @module.handle_action(
          {:event, {:output, :not_an_event}},
          :handle_other,
          %{},
          state
        )
      end
    end

    test "when eos has already been sent", %{state: state} do
      state =
        state
        |> set_playback_state(:playing)
        |> PadModel.set_data!(:output, :end_of_stream?, true)

      assert_raise ActionError, ~r/end ?of ?stream.*sent.*:output/i, fn ->
        @module.handle_action(
          event_action(:output),
          :handle_other,
          %{},
          state
        )
      end
    end

    test "invalid pad direction", %{state: state} do
      state = state |> set_playback_state(:playing)

      assert_raise ActionError, ~r/pad :input.*:input direction/, fn ->
        @module.handle_action(
          event_action(:input),
          :handle_other,
          %{},
          state
        )
      end
    end
  end

  @mock_caps %Membrane.Caps.Mock{integer: 42}
  defp caps_action(pad), do: {:caps, {pad, @mock_caps}}

  describe "handling :caps action" do
    setup :trivial_filter_state

    test "when element is stopped", %{state: state} do
      assert_raise ActionError, ~r/stopped/, fn ->
        @module.handle_action(
          caps_action(:output),
          :handle_other,
          %{},
          state
        )
      end
    end

    test "when pad doesn't exist in the element", %{state: state} do
      state = state |> set_playback_state(:playing)

      assert_raise ActionError, ~r/pad :invalid_pad_ref/i, fn ->
        @module.handle_action(
          caps_action(:invalid_pad_ref),
          :handle_other,
          %{},
          state
        )
      end
    end

    test "when element is playing and caps match the spec", %{state: state} do
      state =
        state
        |> set_playback_state(:playing)
        |> PadModel.set_data!(:output, :accepted_caps, {Membrane.Caps.Mock, [integer: 42]})

      result =
        @module.handle_action(
          caps_action(:output),
          :handle_other,
          %{},
          state
        )

      assert result == {:ok, state |> PadModel.set_data!(:output, :caps, @mock_caps)}
      assert_received Message.new(:caps, @mock_caps, for_pad: :other_ref)
    end

    test "when caps doesn't match specs", %{state: state} do
      state =
        state
        |> set_playback_state(:playing)
        |> PadModel.set_data!(:output, :accepted_caps, {Membrane.Caps.Mock, [integer: 2]})

      assert_raise ActionError, ~r/caps.*(don't|do not) match.*integer: 2/s, fn ->
        @module.handle_action(
          caps_action(:output),
          :handle_other,
          %{},
          state
        )
      end

      refute_received Message.new(:caps, @mock_caps, for_pad: :other_ref)
    end

    test "invalid pad direction", %{state: state} do
      state = state |> set_playback_state(:playing)

      assert_raise ActionError, ~r/pad :input.*:input direction/, fn ->
        @module.handle_action(
          caps_action(:input),
          :handle_other,
          %{},
          state
        )
      end

      refute_received Message.new(:caps, @mock_caps, for_pad: :other_ref)
    end
  end

  @mock_notification :hello_test

  describe "handling :notification action" do
    setup :trivial_filter_state

    test "when parent pid is set", %{state: state} do
      state = %{state | parent_pid: self()}

      result =
        @module.handle_action(
          {:notify, @mock_notification},
          :handle_other,
          %{},
          state
        )

      assert result == {:ok, state}
      assert_received Message.new(:notification, [:elem_name, @mock_notification])
    end
  end

  describe "handling :redemand action" do
    setup :trivial_filter_state

    test "when element is stopped", %{state: state} do
      assert_raise ActionError, ~r/stopped/, fn ->
        @module.handle_action(
          {:redemand, :output},
          :handle_other,
          %{},
          state
        )
      end
    end

    test "when pad doesn't exist in the element", %{state: state} do
      state = state |> set_playback_state(:playing)

      assert_raise ActionError, ~r/pad :invalid_pad_ref/i, fn ->
        @module.handle_action(
          {:redemand, :invalid_pad_ref},
          :handle_other,
          %{},
          state
        )
      end
    end

    test "when pad works in push mode", %{state: state} do
      state = state |> set_playback_state(:playing)

      assert_raise ActionError, ~r/pad :output.*:push mode/i, fn ->
        @module.handle_action(
          {:redemand, :output},
          :handle_other,
          %{},
          state
        )
      end
    end

    test "when pad works in pull mode", %{state: state} do
      state =
        %{state | supplying_demand?: true}
        |> set_playback_state(:playing)
        |> PadModel.set_data!(:output, :mode, :pull)
        |> PadModel.set_data!(:output, :demand_mode, :manual)

      result =
        @module.handle_action(
          {:redemand, :output},
          :handle_other,
          %{},
          state
        )

      assert {:ok, new_state} = result
      assert %{new_state | delayed_demands: MapSet.new()} == state
      assert MapSet.member?(new_state.delayed_demands, {:output, :redemand}) == true
    end
  end

  defp playing_trivial_source(_context) do
    state =
      %{
        State.new(%{
          module: TrivialSource,
          name: :elem_name,
          parent_clock: nil,
          sync: nil,
          parent: self()
        })
        | type: :source,
          pads: %{
            data: %{
              output: %{
                direction: :output,
                pid: self(),
                mode: :pull,
                demand_mode: :manual,
                demand: 0
              }
            }
          }
      }
      |> set_playback_state(:playing)

    [state: state]
  end

  describe "handling_actions" do
    setup :playing_trivial_source

    test "when :redemand is the last action", %{state: state} do
      state = %{state | supplying_demand?: true}

      result =
        @module.handle_actions(
          [notify: :a, notify: :b, redemand: :output],
          :handle_other,
          %{},
          state
        )

      assert_received Message.new(:notification, [:elem_name, :a])
      assert_received Message.new(:notification, [:elem_name, :b])
      assert {:ok, new_state} = result
      assert %{new_state | delayed_demands: MapSet.new()} == state
      assert MapSet.member?(new_state.delayed_demands, {:output, :redemand}) == true
    end

    test "when two :redemand actions are last", %{state: state} do
      state = %{state | supplying_demand?: true}

      result =
        @module.handle_actions(
          [notify: :a, notify: :b, redemand: :output, redemand: :output],
          :handle_other,
          %{},
          state
        )

      assert_received Message.new(:notification, [:elem_name, :a])
      assert_received Message.new(:notification, [:elem_name, :b])
      assert {:ok, new_state} = result
      assert %{new_state | delayed_demands: MapSet.new()} == state
      assert MapSet.member?(new_state.delayed_demands, {:output, :redemand}) == true
    end

    test "when :redemand is not the last action", %{state: state} do
      assert_raise ActionError, ~r/redemand.*last/i, fn ->
        @module.handle_actions(
          [redemand: :output, notify: :a, notify: :b],
          :handle_other,
          %{},
          state
        )
      end

      refute_received Message.new(:notification, [:elem_name, :a])
      refute_received Message.new(:notification, [:elem_name, :b])
    end

    test "when there are no :redemand actions", %{state: state} do
      result =
        @module.handle_actions(
          [notify: :a, notify: :b],
          :handle_other,
          %{},
          state
        )

      assert_received Message.new(:notification, [:elem_name, :a])
      assert_received Message.new(:notification, [:elem_name, :b])
      assert result == {:ok, state}
    end
  end
end
