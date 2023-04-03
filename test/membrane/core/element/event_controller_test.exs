defmodule Membrane.Core.Element.EventControllerTest do
  use ExUnit.Case

  alias Membrane.Core.Element.{DemandCounter, EventController, InputQueue, State}
  alias Membrane.Core.Events
  alias Membrane.Event

  require Membrane.Core.Message

  defmodule MockEventHandlingElement do
    use Membrane.Filter

    def_output_pad :output, flow_control: :manual, accepted_format: _any

    @impl true
    def handle_event(_pad, %Membrane.Event.Underrun{}, _ctx, state) do
      {[], state}
    end
  end

  setup do
    demand_counter =
      DemandCounter.new(
        :pull,
        spawn(fn -> :ok end),
        :buffers,
        spawn(fn -> :ok end),
        :output,
        -300
      )

    input_queue =
      InputQueue.init(%{
        inbound_demand_unit: :buffers,
        outbound_demand_unit: :buffers,
        linked_output_ref: :some_pad,
        log_tag: "test",
        demand_counter: demand_counter,
        target_size: nil,
        min_demand_factor: nil
      })

    state =
      struct(State,
        module: MockEventHandlingElement,
        name: :test_name,
        type: :filter,
        playback: :playing,
        parent_pid: self(),
        synchronization: %{clock: nil, parent_clock: nil, stream_sync: nil},
        pads_data: %{
          input:
            struct(Membrane.Element.PadData,
              ref: :input,
              direction: :input,
              pid: self(),
              flow_control: :manual,
              start_of_stream?: false,
              end_of_stream?: false,
              input_queue: input_queue,
              demand: 0
            )
        }
      )

    assert DemandCounter.get(demand_counter) > 0

    [state: state]
  end

  describe "Event controller handles special event" do
    setup %{state: state} do
      {:ok, sync} = start_supervised({Membrane.Sync, []})
      [state: %{state | synchronization: %{state.synchronization | stream_sync: sync}}]
    end

    test "start of stream successfully", %{state: state} do
      state = EventController.handle_event(:input, %Events.StartOfStream{}, state)
      assert state.pads_data.input.start_of_stream?
    end

    test "ignoring end of stream when there was no start of stream prior", %{state: state} do
      state = EventController.handle_event(:input, %Events.EndOfStream{}, state)
      refute state.pads_data.input.end_of_stream?
      refute state.pads_data.input.start_of_stream?
    end

    test "end of stream successfully", %{state: state} do
      state = put_start_of_stream(state, :input)

      state = EventController.handle_event(:input, %Events.EndOfStream{}, state)
      assert state.pads_data.input.end_of_stream?
    end
  end

  describe "Event controller handles normal events" do
    test "succesfully when callback module returns {[], state}", %{state: state} do
      assert state == EventController.handle_event(:input, %Event.Underrun{}, state)
    end
  end

  defp put_start_of_stream(state, pad_ref) do
    Bunch.Access.update_in(state, [:pads_data, pad_ref], fn data ->
      %{data | start_of_stream?: true}
    end)
  end
end
