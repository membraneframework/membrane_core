defmodule Membrane.Core.Element.EventControllerTest do
  use ExUnit.Case, async: true

  alias Membrane.Core.Element.{AtomicDemand, EventController, InputQueue, State}
  alias Membrane.Core.Events
  alias Membrane.Core.SubprocessSupervisor
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
    atomic_demand =
      AtomicDemand.new(%{
        receiver_effective_flow_control: :pull,
        receiver_process: spawn(fn -> :ok end),
        receiver_demand_unit: :buffers,
        sender_process: spawn(fn -> :ok end),
        sender_pad_ref: :output,
        supervisor: SubprocessSupervisor.start_link!(),
        toilet_capacity: 300
      })

    input_queue =
      InputQueue.init(%{
        inbound_demand_unit: :buffers,
        outbound_demand_unit: :buffers,
        pad_ref: :some_pad,
        log_tag: "test",
        atomic_demand: atomic_demand,
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
        handling_action?: false,
        pads_to_snapshot: MapSet.new(),
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

    assert AtomicDemand.get(atomic_demand) > 0

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
    update_in(state, [:pads_data, pad_ref], fn data ->
      %{data | start_of_stream?: true}
    end)
  end
end
