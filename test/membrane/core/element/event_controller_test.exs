defmodule Membrane.Core.Element.EventControllerTest do
  use ExUnit.Case

  require Membrane.Core.Message

  alias Membrane.Core.Element.{EventController, State}
  alias Membrane.Core.Message
  alias Membrane.Event
  alias Membrane.Pad.Data
  alias Membrane.Core.InputBuffer

  defmodule MockEventHandlingElement do
    use Membrane.Filter

    def_output_pad :output, caps: :any

    @impl true
    def handle_event(_, %Membrane.Event.Discontinuity{}, _ctx, state) do
      {{:error, :cause}, state}
    end

    def handle_event(_, %Membrane.Event.Underrun{}, _ctx, state) do
      {:ok, state}
    end
  end

  setup do
    input_buf = InputBuffer.init(:test, :buffers, false, self(), :some_pad, preferred_size: 10)

    state =
      %{
        State.new(%{module: MockEventHandlingElement, name: :test_name, clock: nil, sync: nil})
        | watcher: self(),
          type: :filter,
          pads: %{
            data: %{
              input: %Data{
                accepted_caps: :any,
                direction: :input,
                pid: self(),
                mode: :pull,
                start_of_stream?: false,
                end_of_stream?: false,
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

  describe "Event controller handles special event" do
    setup %{state: state} do
      {:ok, sync} = start_supervised({Membrane.Sync, []})
      [state: %{state | synchronization: %{state.synchronization | stream_sync: sync}}]
    end

    test "start of stream successfully", %{state: state} do
      assert {:ok, state} = EventController.handle_event(:input, %Event.StartOfStream{}, state)
      assert state.pads.data.input.start_of_stream?
    end

    test "ignoring end of stream when there was no start of stream prior", %{state: state} do
      assert {:ok, state} = EventController.handle_event(:input, %Event.EndOfStream{}, state)
      refute state.pads.data.input.end_of_stream?
      refute state.pads.data.input.start_of_stream?
    end

    test "end of stream successfully", %{state: state} do
      pads =
        Bunch.Access.update_in(state.pads, [:data, :input], fn data ->
          %{data | start_of_stream?: true}
        end)

      state = %{state | pads: pads}

      assert {:ok, state} = EventController.handle_event(:input, %Event.EndOfStream{}, state)
      assert state.pads.data.input.end_of_stream?
    end
  end

  describe "Event controller handles normal events" do
    test "succesfully when callback module returns {:ok, state}", %{state: state} do
      assert {:ok, ^state} = EventController.handle_event(:input, %Event.Underrun{}, state)
    end

    test "processing error returned by callback module", %{state: state} do
      assert {{:error, {:handle_event, :cause}}, ^state} =
               EventController.handle_event(:input, %Event.Discontinuity{}, state)
    end
  end
end
