defmodule Membrane.Core.Element.StreamFormatControllerTest do
  use ExUnit.Case, async: true

  alias Membrane.Buffer
  alias Membrane.Core.Message
  alias Membrane.Core.Element.{InputQueue, State}
  alias Membrane.StreamFormat.Mock, as: MockStreamFormat
  alias Membrane.Support.DemandsTest.Filter

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Core.Message, as: Message

  @module Membrane.Core.Element.StreamFormatController

  setup do
    input_queue =
      InputQueue.init(%{
        inbound_demand_unit: :buffers,
        outbound_demand_unit: :buffers,
        demand_pid: self(),
        demand_pad: :some_pad,
        log_tag: "test",
        toilet?: false,
        target_size: nil,
        min_demand_factor: nil
      })

    state =
      struct(State,
        module: Filter,
        name: :test_name,
        parent: self(),
        type: :filter,
        playback: :playing,
        synchronization: %{clock: nil, parent_clock: nil},
        pads_data: %{
          input:
            struct(Membrane.Element.PadData,
              direction: :input,
              name: :input,
              pid: self(),
              mode: :pull,
              input_queue: input_queue,
              demand: 0
            )
        }
      )

    assert_received Message.new(:demand, _size, for_pad: :some_pad)
    [state: state]
  end

  describe "handle_stream_format for pull pad" do
    test "with empty input_queue", %{state: state} do
      assert PadModel.set_data!(state, :input, :stream_format, %MockStreamFormat{}) ==
               @module.handle_stream_format(:input, %MockStreamFormat{}, state)
    end

    test "with input_queue containing one buffer", %{state: state} do
      state =
        state
        |> PadModel.update_data!(
          :input,
          :input_queue,
          &InputQueue.store(&1, :buffer, %Buffer{payload: "aa"})
        )

      state = @module.handle_stream_format(:input, %MockStreamFormat{}, state)

      assert state.pads_data.input.input_queue.q |> Qex.last!() ==
               {:non_buffer, :stream_format, %MockStreamFormat{}}
    end
  end
end
