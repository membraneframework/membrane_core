defmodule Membrane.Core.Element.StreamFormatControllerTest do
  use ExUnit.Case, async: true

  alias Membrane.Buffer
  alias Membrane.Core.Message
  alias Membrane.Core.Element.{AtomicDemand, InputQueue, State}
  alias Membrane.Core.SubprocessSupervisor
  alias Membrane.StreamFormat.Mock, as: MockStreamFormat
  alias Membrane.Support.DemandsTest.Filter

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Core.Message, as: Message

  @module Membrane.Core.Element.StreamFormatController

  setup do
    atomic_demand =
      AtomicDemand.new(%{
        receiver_effective_flow_control: :pull,
        receiver_process: self(),
        receiver_demand_unit: :buffers,
        sender_process: self(),
        sender_pad_ref: :some_pad,
        supervisor: SubprocessSupervisor.start_link!()
      })

    input_queue =
      InputQueue.init(%{
        inbound_demand_unit: :buffers,
        outbound_demand_unit: :buffers,
        atomic_demand: atomic_demand,
        linked_output_ref: :some_pad,
        log_tag: "test",
        target_size: nil
      })

    state =
      struct(State,
        module: Filter,
        name: :test_name,
        parent: self(),
        type: :filter,
        playback: :playing,
        synchronization: %{clock: nil, parent_clock: nil},
        handling_callback?: false,
        pads_to_snapshot: MapSet.new(),
        pads_data: %{
          input:
            struct(Membrane.Element.PadData,
              direction: :input,
              name: :input,
              pid: self(),
              flow_control: :manual,
              input_queue: input_queue,
              demand: 0
            )
        }
      )

    assert_received Message.new(:atomic_demand_increased, :some_pad)
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
