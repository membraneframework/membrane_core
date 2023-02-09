defmodule Membrane.Core.ElementTest do
  use ExUnit.Case, async: true

  alias __MODULE__.SomeElement
  alias Membrane.Core.Element
  alias Membrane.Core.Message
  alias Membrane.Core.Parent.Link.Endpoint

  require Membrane.Core.Message

  defmodule SomeElement do
    use Membrane.Source
    def_output_pad :output, flow_control: :manual, accepted_format: _any

    def_options test_pid: [spec: pid | nil, default: nil]

    @impl true
    def handle_info(msg, _ctx, state) do
      {[notify_parent: msg], state}
    end
  end

  defmodule Filter do
    use Membrane.Filter

    def_output_pad :output, flow_control: :manual, accepted_format: _any

    def_input_pad :dynamic_input,
      flow_control: :manual,
      accepted_format: _any,
      demand_unit: :buffers,
      availability: :on_request

    @impl true
    def handle_tick(_timer, _ctx, state) do
      {[], state}
    end

    @impl true
    def handle_demand(:output, size, _unit, _ctx, state) do
      {[demand: {:dynamic_input, size}], state}
    end
  end

  defmodule StreamFormat do
    defstruct []
  end

  defp get_state do
    {:ok, state, {:continue, :setup}} =
      Element.init(%{
        module: Filter,
        user_options: nil,
        name: :some_element,
        parent_clock: nil,
        sync: Membrane.Sync.no_sync(),
        parent: self(),
        parent_path: [],
        log_metadata: [],
        subprocess_supervisor: Membrane.Core.SubprocessSupervisor.start_link!(),
        parent_supervisor: Membrane.Core.SubprocessSupervisor.start_link!(),
        group: nil
      })

    state
  end

  defp linked_state do
    {:reply, {:ok, _reply}, state} =
      Element.handle_call(
        Message.new(:handle_link, [
          :output,
          %Endpoint{pad_spec: :output, pad_ref: :output, pad_props: %{options: []}, child: :this},
          %Endpoint{
            pad_spec: :dynamic_input,
            pad_ref: :dynamic_input,
            pid: self(),
            child: :other,
            pad_props: %{options: [], toilet_capacity: nil, throttling_factor: nil}
          },
          %{
            initiator: :sibling,
            other_info: %{direction: :input, flow_control: :manual, demand_unit: :buffers},
            link_metadata: %{toilet: nil, observability_metadata: %{}},
            stream_format_validation_params: []
          }
        ]),
        nil,
        get_state()
      )

    {:reply, {:ok, _reply}, state} =
      Element.handle_call(
        Message.new(:handle_link, [
          :input,
          %Endpoint{
            pad_spec: :dynamic_input,
            pad_ref: :dynamic_input,
            pad_props: %{
              options: [],
              toilet_capacity: nil,
              target_queue_size: nil,
              auto_demand_size: nil,
              min_demand_factor: nil,
              throttling_factor: 1
            },
            child: :this,
            pid: self()
          },
          %Endpoint{pad_spec: :output, pad_ref: :output, pid: self(), child: :other},
          %{
            initiator: :sibling,
            other_info: %{direction: :output, flow_control: :manual},
            link_metadata: %{toilet: nil, observability_metadata: %{}},
            stream_format_validation_params: []
          }
        ]),
        nil,
        state
      )

    state
  end

  defp playing_state do
    {:noreply, state} = Element.handle_info(Message.new(:play), linked_state())
    state
  end

  test "should raise when static pads not linked when getting play request" do
    assert_raise Membrane.LinkError, fn ->
      assert {:noreply, _state} = Element.handle_info(Message.new(:play), get_state())
    end
  end

  test "should return correct clock and should not modify the state" do
    original_state = get_state()

    assert {:reply, reply, state} =
             Element.handle_call(
               Message.new(:get_clock),
               nil,
               original_state
             )

    assert reply == state.synchronization.clock
    assert state == original_state
  end

  test "should store demand/buffer/event/stream format when not playing" do
    initial_state = linked_state()

    [
      Message.new(:demand, 10, for_pad: :output),
      Message.new(:buffer, %Membrane.Buffer{payload: <<>>}, for_pad: :dynamic_input),
      Message.new(:stream_format, %StreamFormat{}, for_pad: :dynamic_input),
      Message.new(:event, %Membrane.Testing.Event{}, for_pad: :dynamic_input),
      Message.new(:event, %Membrane.Testing.Event{}, for_pad: :output)
    ]
    |> Enum.each(fn msg ->
      assert {:noreply, state} = Element.handle_info(msg, initial_state)
      assert %{state | playback_queue: []} == initial_state
      assert [fun] = state.playback_queue
      assert is_function(fun)
    end)
  end

  test "should update demand" do
    msg = Message.new(:demand, 10, for_pad: :output)
    assert {:noreply, state} = Element.handle_info(msg, playing_state())
    assert state.pads_data.output.demand == 10
  end

  test "should store incoming buffers in dynamic_input buffer" do
    msg = Message.new(:buffer, [%Membrane.Buffer{payload: <<123>>}], for_pad: :dynamic_input)
    assert {:noreply, state} = Element.handle_info(msg, playing_state())
    assert state.pads_data.dynamic_input.input_queue.size == 1
  end

  test "should assign incoming stream_format to the pad and forward them" do
    assert {:noreply, state} =
             Element.handle_info(
               Message.new(:stream_format, %StreamFormat{}, for_pad: :dynamic_input),
               playing_state()
             )

    assert state.pads_data.dynamic_input.stream_format == %StreamFormat{}
    assert state.pads_data.output.stream_format == %StreamFormat{}

    assert_receive Message.new(:stream_format, %StreamFormat{}, for_pad: :dynamic_input)
  end

  test "should forward events" do
    [
      Message.new(:event, %Membrane.Testing.Event{}, for_pad: :dynamic_input),
      Message.new(:event, %Membrane.Testing.Event{}, for_pad: :output)
    ]
    |> Enum.each(fn msg ->
      assert {:noreply, _state} = Element.handle_info(msg, playing_state())
      assert_receive ^msg
    end)
  end

  test "should handle linking pads and reply with pad info" do
    pid = self()

    assert {:reply, {:ok, reply}, state} =
             Element.handle_call(
               Message.new(:handle_link, [
                 :output,
                 %{
                   pad_ref: :output,
                   pad_props: %{options: [], toilet_capacity: nil},
                   child: :this
                 },
                 %{
                   pad_ref: :dynamic_input,
                   pid: pid,
                   child: :other,
                   pad_props: %{options: [], toilet_capacity: nil, throttling_factor: nil}
                 },
                 %{
                   initiator: :sibling,
                   other_info: %{
                     direction: :input,
                     demand_unit: :buffers,
                     flow_control: :manual
                   },
                   link_metadata: %{observability_metadata: %{}},
                   stream_format_validation_params: []
                 }
               ]),
               nil,
               get_state()
             )

    assert {%{child: :this, pad_props: %{options: []}, pad_ref: :output},
            %{
              availability: :always,
              flow_control: :manual,
              direction: :output,
              name: :output,
              options: nil
            },
            %{toilet: toilet, output_demand_unit: :buffers, input_demand_unit: :buffers}} = reply

    assert toilet != nil

    assert %Membrane.Element.PadData{
             pid: ^pid,
             other_ref: :dynamic_input,
             other_demand_unit: :buffers
           } = state.pads_data.output
  end

  test "should handle unlinking pads" do
    assert {:noreply, state} =
             Element.handle_info(Message.new(:handle_unlink, :dynamic_input), linked_state())

    refute Map.has_key?(state.pads_data, :dynamic_input)
  end

  test "should update timer on each tick" do
    {:ok, clock} = Membrane.Clock.start_link()
    state = Membrane.Core.TimerController.start_timer(:timer, 1000, clock, get_state())
    assert {:noreply, state} = Element.handle_info(Message.new(:timer_tick, :timer), state)
    assert state.synchronization.timers.timer.next_tick_time == 2000
  end

  test "should update clock ratio" do
    {:ok, clock} = Membrane.Clock.start_link()
    state = Membrane.Core.TimerController.start_timer(:timer, 1000, clock, get_state())

    assert {:noreply, state} =
             Element.handle_info({:membrane_clock_ratio, clock, Ratio.new(123)}, state)

    assert state.synchronization.timers.timer.ratio == Ratio.new(123)
  end

  test "should set stream sync" do
    assert {:reply, :ok, state} =
             Element.handle_call(Message.new(:set_stream_sync, :sync), nil, get_state())

    assert state.synchronization.stream_sync == :sync
  end

  test "should fail on invalid message" do
    [
      Message.new(:abc),
      Message.new(:abc, :def),
      Message.new(:abc, :def, for_pad: :dynamic_input)
    ]
    |> Enum.each(fn msg ->
      assert_raise Membrane.ElementError, fn -> Element.handle_info(msg, get_state()) end

      assert_raise Membrane.ElementError, fn ->
        Element.handle_call(msg, {self(), nil}, get_state())
      end
    end)
  end

  test "other message" do
    state = get_state()
    assert {:noreply, state} == Element.handle_info(:abc, state)
  end

  describe "Not linked element" do
    test "DOWN message should be delivered to handle_info" do
      parent_pid = self()

      {:ok, elem_pid} =
        parent_pid
        |> element_init_options
        |> Element.start()

      monitored_proc = spawn(fn -> receive do: (:exit -> :ok) end)
      on_exit(fn -> send(monitored_proc, :exit) end)
      ref = make_ref()
      send(elem_pid, {:DOWN, ref, :process, monitored_proc, :normal})

      assert_receive Message.new(:child_notification, [
                       :name,
                       {:DOWN, ^ref, :process, ^monitored_proc, :normal}
                     ])

      send(elem_pid, {:DOWN, ref, :process, parent_pid, :normal})

      assert_receive Message.new(:child_notification, [
                       :name,
                       {:DOWN, ^ref, :process, ^parent_pid, :normal}
                     ])

      assert Process.alive?(elem_pid)
    end
  end

  defp element_init_options(pipeline) do
    %{
      module: SomeElement,
      name: :name,
      node: nil,
      user_options: %{test_pid: self()},
      parent: pipeline,
      parent_clock: nil,
      sync: Membrane.Sync.no_sync(),
      parent_path: [],
      log_metadata: [],
      subprocess_supervisor: Membrane.Core.SubprocessSupervisor.start_link!(),
      parent_supervisor: Membrane.Core.SubprocessSupervisor.start_link!(),
      group: nil
    }
  end
end
