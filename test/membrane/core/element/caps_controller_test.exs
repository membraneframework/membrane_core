defmodule Membrane.Core.Element.CapsControllerTest do
  use ExUnit.Case, async: true

  alias Membrane.Buffer
  alias Membrane.Caps.Mock, as: MockCaps
  alias Membrane.Core.Message
  alias Membrane.Core.Element.{InputQueue, State}
  alias Membrane.Support.DemandsTest.Filter

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Core.Message, as: Message

  @module Membrane.Core.Element.CapsController

  setup do
    input_queue =
      InputQueue.init(%{
        demand_unit: :buffers,
        demand_pid: self(),
        demand_pad: :some_pad,
        log_tag: "test",
        toilet?: false,
        target_size: nil,
        min_demand_factor: nil
      })

    state =
      %{
        State.new(%{
          module: Filter,
          name: :test_name,
          parent_clock: nil,
          sync: nil,
          parent: self()
        })
        | type: :filter,
          pads_data: %{
            input:
              struct(Membrane.Element.PadData,
                accepted_caps: :any,
                direction: :input,
                pid: self(),
                mode: :pull,
                input_queue: input_queue,
                demand: 0
              )
          }
      }
      |> Bunch.Struct.put_in([:playback, :state], :playing)

    assert_received Message.new(:demand, _size, for_pad: :some_pad)
    [state: state]
  end

  describe "handle_caps for pull pad" do
    test "with empty input_queue", %{state: state} do
      assert {:ok, _state} = @module.handle_caps(:input, %MockCaps{}, state)
    end

    test "with input_queue containing one buffer", %{state: state} do
      state =
        state
        |> PadModel.update_data!(
          :input,
          :input_queue,
          &InputQueue.store(&1, :buffer, %Buffer{payload: "aa"})
        )

      assert {:ok, new_state} = @module.handle_caps(:input, %MockCaps{}, state)

      assert new_state.pads_data.input.input_queue.q |> Qex.last!() ==
               {:non_buffer, :caps, %MockCaps{}}
    end
  end
end
