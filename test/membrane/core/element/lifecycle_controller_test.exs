defmodule Membrane.Core.Element.LifecycleControllerTest do
  use ExUnit.Case, async: true

  alias Membrane.Core.Element.{AtomicDemand, InputQueue, LifecycleController, State}

  alias Membrane.Core.{
    Message,
    SubprocessSupervisor
  }

  require Membrane.Core.Message

  defmodule DummyElement do
    use Membrane.Filter
    def_output_pad :output, flow_control: :manual, accepted_format: _any

    @impl true
    def handle_terminate_request(_ctx, state) do
      {[], state}
    end
  end

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
        pad_ref: :some_pad,
        log_tag: "test",
        target_size: nil
      })

    state =
      struct!(State,
        module: DummyElement,
        name: :test_name,
        type: :filter,
        playback: :playing,
        parent_pid: self(),
        synchronization: %{clock: nil, parent_clock: nil},
        # handling_action?: false,
        supplying_demand?: false,
        pads_to_snapshot: MapSet.new(),
        delayed_demands: MapSet.new(),
        pads_data: %{
          input:
            struct(Membrane.Element.PadData,
              ref: :input,
              direction: :input,
              pid: self(),
              flow_control: :manual,
              start_of_stream?: true,
              end_of_stream?: false,
              input_queue: input_queue,
              demand: 0
            )
        },
        satisfied_auto_output_pads: MapSet.new(),
        awaiting_auto_input_pads: MapSet.new(),
        auto_input_pads: []
      )

    assert_received Message.new(:atomic_demand_increased, :some_pad)
    [state: state]
  end

  test "End of stream is generated upon termination", %{
    state: state
  } do
    state = LifecycleController.handle_terminate_request(state)
    assert state.pads_data.input.end_of_stream?
  end
end
