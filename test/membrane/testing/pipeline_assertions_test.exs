defmodule Membrane.Testing.PipelineAssertionsTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Testing.Pipeline
  alias Membrane.Testing.Pipeline.State

  # Note: Most of tests in this file are just to force compile valid macro invocations
  # Note: so compiler can find the errors.

  setup do
    [state: %State{test_process: self(), module: nil}]
  end

  describe "assert_pipeline_notified" do
    test "does not flunk when notification is handled", %{
      state: state
    } do
      Pipeline.handle_child_notification(:child_notification, :element, context(), state)
      assert_pipeline_notified(self(), :element, :child_notification)
    end

    test "flunks when pipeline is not notified" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_pipeline_notified(self(), :element, :child_notification, 0)
      end
    end
  end

  describe "assert_pipeline_playback_changed" do
    test "does not flunk when state change is handled", %{
      state: state
    } do
      Pipeline.handle_prepared_to_stopped(context(), state)
      assert_pipeline_playback_changed(self(), :prepared, :stopped)
    end

    test "flunks when state is not changed" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_pipeline_playback_changed(self(), :prepared, :stopped, 0)
      end
    end

    test "flunks when state change does not match given one", %{state: state} do
      Pipeline.handle_prepared_to_stopped(context(), state)

      assert_raise ExUnit.AssertionError, fn ->
        assert_pipeline_playback_changed(self(), :stopped, :prepared, 0)
      end
    end

    test "supports pattern as argument", %{
      state: state
    } do
      Pipeline.handle_prepared_to_stopped(context(), state)
      prev_state = :prepared
      current_state = :stopped
      assert_pipeline_playback_changed(self(), ^prev_state, ^current_state)
    end

    test "flunks when state is not changed when patterns are provided" do
      assert_raise ExUnit.AssertionError, fn ->
        prev_state = :prepared
        current_state = :stopped
        assert_pipeline_playback_changed(self(), ^prev_state, ^current_state, 0)
      end
    end

    test "flunks when state change does not match provided pattern", %{
      state: state
    } do
      Pipeline.handle_stopped_to_prepared(context(), state)

      assert_raise ExUnit.AssertionError, fn ->
        prev_state = :prepared
        current_state = :stopped
        assert_pipeline_playback_changed(self(), ^prev_state, ^current_state, 0)
      end
    end

    test "raises an error if invalid arguments are provided" do
      pattern =
        """
        \\s*Transition from stopped to playing is not valid\.\
        \\s*Valid transitions are:\
        \\s*stopped -> prepared\
        \\s*prepared -> playing\
        \\s*playing -> prepared\
        \\s*prepared -> stopped\s*
        """
        |> Regex.compile!()

      assert_raise(
        ExUnit.AssertionError,
        pattern,
        fn ->
          assert_pipeline_playback_changed(self(), :stopped, :playing)
        end
      )
    end

    test "allows for wildcard as first argument", %{state: state} do
      Pipeline.handle_prepared_to_stopped(context(), state)
      assert_pipeline_playback_changed(self(), _, :stopped)
    end

    test "allows for wildcard as second argument", %{state: state} do
      Pipeline.handle_playing_to_prepared(context(), state)
      assert_pipeline_playback_changed(self(), :playing, _)
    end

    test "when using wildcard as first argument flunks if state hasn't changed" do
      assert_raise(ExUnit.AssertionError, fn ->
        assert_pipeline_playback_changed(self(), _, :stopped, 0)
      end)
    end

    test "when using wildcard as second argument flunks if state hasn't changed" do
      assert_raise(ExUnit.AssertionError, fn ->
        assert_pipeline_playback_changed(self(), :prepared, _, 0)
      end)
    end
  end

  describe "assert_pipeline_receive" do
    test "does not flunk when pipeline receives a message", %{state: state} do
      message = "I am an important message"
      Pipeline.handle_info(message, context(), state)
      assert_pipeline_receive(self(), ^message)
    end

    test "flunks when pipeline does not receive a message" do
      message = "I am an important message"

      assert_raise ExUnit.AssertionError, fn ->
        assert_pipeline_receive(self(), ^message, 0)
      end
    end
  end

  describe "refute_pipeline_receive" do
    test "does not flunk when pipeline does not receive message" do
      message = "I am an important message"
      refute_pipeline_receive(self(), ^message, 0)
    end

    test "flunks when pipeline receives message", %{state: state} do
      message = "I am an important message"
      Pipeline.handle_info(message, context(), state)

      assert_raise ExUnit.AssertionError, fn ->
        refute_pipeline_receive(self(), ^message)
      end
    end
  end

  describe "assert_sink_caps" do
    test "does not flunk when caps are handled", %{state: state} do
      caps = %{property: :value}
      Pipeline.handle_child_notification({:caps, :input, caps}, :sink, context(), state)
      assert_sink_caps(self(), :sink, ^caps)
    end

    test "flunks when caps are not handled" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_sink_caps(self(), :sink, _, 0)
      end
    end
  end

  describe "refute_sink_caps" do
    test "flunks when caps are handled", %{state: state} do
      caps = %{property: :value}
      Pipeline.handle_child_notification({:caps, :input, caps}, :sink, context(), state)

      assert_raise ExUnit.AssertionError, fn ->
        refute_sink_caps(self(), :sink, ^caps)
      end
    end

    test "does not flunk when caps are not handled" do
      refute_sink_caps(self(), :sink, _, 0)
    end
  end

  describe "assert_sink_event" do
    test "does not flunk when event is handled", %{state: state} do
      event = %Membrane.Event.Discontinuity{}
      Pipeline.handle_child_notification({:event, event}, :sink, context(), state)
      assert_sink_event(self(), :sink, ^event)
    end

    test "flunks when event is not handled" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_sink_event(self(), :sink, _, 0)
      end
    end
  end

  describe "refute_sink_event" do
    test "flunks when event is handled", %{state: state} do
      event = %Membrane.Event.Discontinuity{}
      Pipeline.handle_child_notification({:event, event}, :sink, context(), state)

      assert_raise ExUnit.AssertionError, fn ->
        refute_sink_event(self(), :sink, ^event)
      end
    end

    test "does not flunk when event is not handled" do
      refute_sink_event(self(), :sink, %Membrane.Event.Discontinuity{}, 0)
    end
  end

  describe "assert_sink_buffer" do
    test "does not flunk when buffer is handled", %{state: state} do
      buffer = %Membrane.Buffer{payload: 255}
      Pipeline.handle_child_notification({:buffer, buffer}, :sink, context(), state)
      assert_sink_buffer(self(), :sink, ^buffer)
    end

    test "flunks when buffer is not handled" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_sink_buffer(self(), :sink, _, 0)
      end
    end
  end

  describe "refute_sink_buffer" do
    test "flunks when buffer is handled", %{state: state} do
      buffer = %Membrane.Buffer{payload: 255}
      Pipeline.handle_child_notification({:buffer, buffer}, :sink, context(), state)

      assert_raise ExUnit.AssertionError, fn ->
        refute_sink_buffer(self(), :sink, ^buffer)
      end
    end

    test "does not flunk when event is not handled" do
      refute_sink_buffer(self(), :sink, %Membrane.Buffer{payload: 10}, 0)
    end
  end

  describe "assert_start_of_stream" do
    test "does not flunk when :start_of_stream is handled by pipeline", %{state: state} do
      Pipeline.handle_element_start_of_stream(:sink, :input, context(), state)
      assert_start_of_stream(self(), :sink)
    end

    test "flunks when :start_of_stream is not handled by the pipeline" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_start_of_stream(self(), :sink, :input, 0)
      end
    end
  end

  describe "assert_end_of_stream" do
    test "does not flunk when :end_of_stream is handled by pipeline", %{state: state} do
      Pipeline.handle_element_end_of_stream(:sink, :input, context(), state)
      assert_end_of_stream(self(), :sink)
    end

    test "flunks when :end_of_stream is not handled by the pipeline" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_end_of_stream(self(), :sink, :input, 0)
      end
    end
  end

  defp context(), do: nil
end
