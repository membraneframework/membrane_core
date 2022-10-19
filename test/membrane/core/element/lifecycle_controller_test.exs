defmodule Membrane.Core.Element.LifecycleControllerTest do
  use ExUnit.Case

  alias Membrane.Core.Element.{InputQueue, LifecycleController, State}
  alias Membrane.Core.Message

  require Membrane.Core.Message

  defmodule DummyElement do
    use Membrane.Filter
    def_output_pad :output, caps: :any

    @impl true
    def handle_terminate_request(_ctx, state) do
      {:ok, state}
    end
  end

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
      struct(State,
        module: DummyElement,
        name: :test_name,
        type: :filter,
        playback: :playing,
        parent_pid: self(),
        synchronization: %{clock: nil, parent_clock: nil},
        pads_data: %{
          input:
            struct(Membrane.Element.PadData,
              ref: :input,
              accepted_caps: :any,
              direction: :input,
              pid: self(),
              mode: :pull,
              start_of_stream?: true,
              end_of_stream?: false,
              input_queue: input_queue,
              demand: 0
            )
        }
      )

    assert_received Message.new(:demand, _size, for_pad: :some_pad)
    [state: state]
  end

  test "End of stream is generated upon termination", %{
    state: state
  } do
    state = LifecycleController.handle_terminate_request(state)
    assert state.pads_data.input.end_of_stream?
  end
end
