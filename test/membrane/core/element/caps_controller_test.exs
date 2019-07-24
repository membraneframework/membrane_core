defmodule Membrane.Core.Element.CapsControllerTest do
  use ExUnit.Case, async: true

  alias Membrane.Buffer
  alias Membrane.Caps.Mock, as: MockCaps
  alias Membrane.Core.{InputBuffer, Message}
  alias Membrane.Core.Element.{PadModel, State}
  alias Membrane.Element.Pad.Data
  alias Membrane.Support.DemandsTest.Filter

  require Message

  @module Membrane.Core.Element.CapsController

  setup do
    input_buf = InputBuffer.init(:test, :buffers, false, self(), :some_pad, preferred_size: 10)

    state =
      %{
        State.new(Filter, :test_name)
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

    assert_received Message.new(:demand, [10], from_pad: :some_pad)
    [state: state]
  end

  describe "handle_caps for pull pad" do
    test "with empty input_buf", %{state: state} do
      assert {:ok, new_state} = @module.handle_caps(:input, %MockCaps{}, state)
    end

    test "with input_buf containing one buffer", %{state: state} do
      state =
        state
        |> PadModel.update_data!(
          :input,
          :input_buf,
          fn input_buf ->
            {:ok, input_buf} = InputBuffer.store(input_buf, :buffer, %Buffer{payload: "aa"})
            input_buf
          end
        )

      assert {:ok, new_state} = @module.handle_caps(:input, %MockCaps{}, state)

      assert new_state.pads.data.input.input_buf.q |> Qex.last!() ==
               {:non_buffer, :caps, %MockCaps{}}
    end
  end
end
