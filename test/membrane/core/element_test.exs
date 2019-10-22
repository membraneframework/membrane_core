defmodule Membrane.Core.ElementTest do
  use ExUnit.Case, async: true

  defmodule SomeElement do
    use Membrane.Source
    def_output_pad :output, caps: :any

    @impl true
    def handle_other(msg, _ctx, state) do
      {{:ok, notify: msg}, state}
    end
  end

  require Membrane.Core.Message

  alias __MODULE__.SomeElement
  alias Membrane.Core.Element
  alias Membrane.Core.Message

  defp get_state do
    {:ok, state} =
      Element.init(%{
        module: Membrane.Support.Element.TrivialFilter,
        user_options: nil,
        name: :some_element,
        clock: nil,
        sync: Membrane.Sync.no_sync(),
        parent: self()
      })

    state
  end

  defp linked_state do
    {:reply, {:ok, _reply}, state} =
      Element.handle_call(
        Message.new(:handle_link, [:output, :output, self(), :input, %{mode: :pull}, []]),
        nil,
        get_state()
      )

    {:reply, {:ok, _reply}, state} =
      Element.handle_call(
        Message.new(:handle_link, [:input, :input, self(), :output, %{mode: :pull}, []]),
        nil,
        state
      )

    {:reply, :ok, state} = Element.handle_call(Message.new(:linking_finished), nil, state)

    state
  end

  defp playing_state do
    {:noreply, state} =
      Element.handle_info(Message.new(:change_playback_state, :playing), linked_state())

    state
  end

  test "change playback state" do
    assert {:noreply, state} =
             Element.handle_info(Message.new(:change_playback_state, :prepared), get_state())

    assert state.playback.state == :prepared

    assert {:noreply, state} =
             Element.handle_info(Message.new(:change_playback_state, :playing), state)

    assert state.playback.state == :playing

    assert {:noreply, state} =
             Element.handle_info(Message.new(:change_playback_state, :prepared), state)

    assert state.playback.state == :prepared

    assert {:noreply, state} =
             Element.handle_info(Message.new(:change_playback_state, :stopped), state)

    assert state.playback.state == :stopped

    assert {:noreply, state} =
             Element.handle_info(Message.new(:change_playback_state, :playing), state)

    assert state.playback.state == :playing
  end

  test "handle watcher" do
    assert {:reply, {:ok, reply}, state} =
             Element.handle_call(Message.new(:handle_watcher, :pid), nil, get_state())

    assert reply == %{clock: state.synchronization.clock}
    assert state.watcher == :pid
  end

  test "set controlling pid" do
    assert {:reply, :ok, state} =
             Element.handle_call(Message.new(:set_controlling_pid, :pid), nil, get_state())

    assert state.controlling_pid == :pid
  end

  test "demand unit" do
    assert {:noreply, state} =
             Element.handle_info(Message.new(:demand_unit, [:bytes, :output]), linked_state())

    assert state.pads.data.output.other_demand_unit == :bytes
  end

  test "demand or buffer or caps or event when not playing" do
    initial_state = linked_state()

    [
      Message.new(:demand, 10, for_pad: :output),
      Message.new(:buffer, %Membrane.Buffer{payload: <<>>}, for_pad: :input),
      Message.new(:caps, :caps, for_pad: :input),
      Message.new(:event, %Membrane.Testing.Event{}, for_pad: :input),
      Message.new(:event, %Membrane.Testing.Event{}, for_pad: :output)
    ]
    |> Enum.each(fn msg ->
      assert {:noreply, state} = Element.handle_info(msg, initial_state)
      assert {:ok, state} == Element.PlaybackBuffer.store(msg, initial_state)
    end)
  end

  test "demand" do
    assert {:stop, {:error, {:cannot_handle_message, :handle_demand_not_implemented, _}}, state} =
             Element.handle_info(Message.new(:demand, 10, for_pad: :output), playing_state())

    assert state.pads.data.output.demand == 10
  end

  test "buffer" do
    assert {:noreply, state} =
             Element.handle_info(
               Message.new(:buffer, [%Membrane.Buffer{payload: <<123>>}], for_pad: :input),
               playing_state()
             )

    assert state.pads.data.input.input_buf.current_size == 1
  end

  test "caps" do
    assert {:noreply, state} =
             Element.handle_info(Message.new(:caps, :caps, for_pad: :input), playing_state())

    assert state.pads.data.input.caps == :caps
    assert state.pads.data.output.caps == :caps

    assert_receive Message.new(:caps, :caps, for_pad: :input)
  end

  test "event" do
    [
      Message.new(:event, %Membrane.Testing.Event{}, for_pad: :input),
      Message.new(:event, %Membrane.Testing.Event{}, for_pad: :output)
    ]
    |> Enum.each(fn msg ->
      assert {:noreply, _state} = Element.handle_info(msg, playing_state())
      assert_receive msg
    end)
  end

  test "linking" do
    pid = self()

    assert {:reply, {:ok, reply}, state} =
             Element.handle_call(
               Message.new(:handle_link, [:output, :output, pid, :input, %{mode: :pull}, []]),
               nil,
               get_state()
             )

    assert reply == %{
             accepted_caps: :any,
             availability: :always,
             bin?: false,
             direction: :output,
             mode: :pull,
             options: nil
           }

    assert %Membrane.Pad.Data{pid: ^pid, other_ref: :input} = state.pads.data.output

    assert {:reply, :ok, _state} = Element.handle_call(Message.new(:linking_finished), nil, state)
  end

  test "handle unlink" do
    assert {:noreply, state} =
             Element.handle_info(Message.new(:handle_unlink, :input), linked_state())

    refute Map.has_key?(state.pads.data, :input)
  end

  test "timer tick" do
    assert {:noreply, _state} = Element.handle_info(Message.new(:timer_tick, 1), get_state())
  end

  test "membrane clock ratio" do
    assert {:noreply, _state} =
             Element.handle_info({:membrane_clock_ratio, :clock, :ratio}, get_state())
  end

  test "set stream sync" do
    assert {:reply, :ok, state} =
             Element.handle_call(Message.new(:set_stream_sync, :sync), nil, get_state())

    assert state.synchronization.stream_sync == :sync
  end

  test "invalid message" do
    [
      Message.new(:abc),
      Message.new(:abc, :def),
      Message.new(:abc, :def, for_pad: :input)
    ]
    |> Enum.each(fn msg ->
      assert {:stop, {:error, {:cannot_handle_message, {:invalid_message, ^msg, _}, _}}, _state} =
               Element.handle_info(msg, get_state())

      assert {:reply, {:error, {:cannot_handle_message, {:invalid_message, ^msg, _}, _}}, _state} =
               Element.handle_call(msg, nil, get_state())
    end)

    assert {:reply, {:error, {:cannot_handle_message, {:invalid_message, :abc, _}, _}}, _state} =
             Element.handle_call(:abc, nil, get_state())
  end

  test "other message" do
    state = get_state()
    assert {:noreply, state} == Element.handle_info(:abc, state)
  end

  describe "Not linked element" do
    test "should shutdown when pipeline is down" do
      monitored_proc = spawn(fn -> receive do: (:exit -> :ok) end)

      {:ok, elem_pid} =
        monitored_proc
        |> element_init_options
        |> Element.start()

      {:ok, _clock} = Message.call(elem_pid, :handle_watcher, self())
      ref = Process.monitor(elem_pid)
      send(monitored_proc, :exit)
      assert_receive {:DOWN, ^ref, :process, ^elem_pid, :normal}
    end

    test "should not assume pipeline is down when getting any monitor message" do
      monitored_proc = spawn(fn -> receive do: (:exit -> :ok) end)
      on_exit(fn -> send(monitored_proc, :exit) end)

      {:ok, elem_pid} =
        monitored_proc
        |> element_init_options
        |> Element.start()

      {:ok, _clock} = Message.call(elem_pid, :handle_watcher, self())
      ref = make_ref()
      deceased_pid = self()
      send(elem_pid, {:DOWN, ref, :process, deceased_pid, :normal})

      assert_receive Message.new(:notification, [
                       :name,
                       {:DOWN, ^ref, :process, ^deceased_pid, :normal}
                     ])

      assert Process.alive?(elem_pid)
    end
  end

  defp element_init_options(pipeline) do
    %{
      module: SomeElement,
      name: :name,
      user_options: %{},
      parent: pipeline,
      clock: nil,
      sync: Membrane.Sync.no_sync()
    }
  end
end
