defmodule Membrane.Core.Element.CapsControllerTest do
  use ExUnit.Case, async: true

  alias Membrane.Buffer
  alias Membrane.Caps.Mock, as: MockCaps
  alias Membrane.Core.{InputBuffer, Message}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.State
  alias Membrane.Pad.Data
  alias Membrane.Support.DemandsTest.Filter

  require Message

  @module Membrane.Core.Element.CapsController

  setup do
    input_buf = InputBuffer.init(:buffers, self(), :some_pad, "test", preferred_size: 10)

    state =
      %{
        State.new(%{module: Filter, name: :test_name, parent_clock: nil, sync: nil})
        | watcher: self(),
          type: :filter,
          pads: %{
            data: %{
              input: %Data{
                accepted_caps: :any,
                direction: :input,
                pid: self(),
                mode: :pull,
                input_buf: input_buf,
                demand: 0
              }
            }
          }
      }
      |> Bunch.Struct.put_in([:playback, :state], :playing)

    assert_received Message.new(:demand, 10, for_pad: :some_pad)
    [state: state]
  end

  describe "handle_caps for pull pad" do
    test "with empty input_buf", %{state: state} do
      assert {:ok, _state} = @module.handle_caps(:input, %MockCaps{}, state)
    end

    test "with input_buf containing one buffer", %{state: state} do
      state =
        state
        |> PadModel.update_data!(
          :input,
          :input_buf,
          &InputBuffer.store(&1, :buffer, %Buffer{payload: "aa"})
        )

      assert {:ok, new_state} = @module.handle_caps(:input, %MockCaps{}, state)

      assert new_state.pads.data.input.input_buf.q |> Qex.last!() ==
               {:non_buffer, :caps, %MockCaps{}}
    end
  end
end
