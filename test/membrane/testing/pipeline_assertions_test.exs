defmodule Membrane.Testing.PipelineAssertionsTest do
  use ExUnit.Case
  alias Membrane.Testing.Pipeline
  import Membrane.Testing.Assertions

  # Note: Most of tests in this file are just to force compile valid macro invocations
  # Note: so compiler can find the errors.

  setup do
    [state: %{test_process: self()}]
  end

  describe "assert_pipeline_notified" do
    test "does not flunk when notification is handled", %{
      state: state
    } do
      Pipeline.handle_notification(:notification, :element, state)
      assert_pipeline_notified(self(), :element, :notification)
    end

    test "flunks when pipeline is not notified" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_pipeline_notified(self(), :element, :notification, 0)
      end
    end
  end

  describe "assert_pipeline_playback_changed" do
    test "does not flunk when state change is handled", %{
      state: state
    } do
      Pipeline.handle_prepared_to_stopped(state)
      assert_pipeline_playback_changed(self(), :prepared, :stopped)
    end

    test "flunks when state is not changed" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_pipeline_playback_changed(self(), :prepared, :stopped, 0)
      end
    end

    test "raises an error if invalid arguments are provided" do
      assert_raise(
        RuntimeError,
        """
        Transition from stopped to playing is not valid.
        Valid transitions are:
          stopped -> prepared
          prepared -> playing
          playing -> prepared
          prepared -> stopped
        """,
        fn ->
          assert_pipeline_playback_changed(self(), :stopped, :playing)
        end
      )
    end
  end

  describe "assert_pipeline_received" do
    test "does not flunk when pipeline receives the message", %{state: state} do
      message = "I am important message"
      Pipeline.handle_other(message, state)
      assert_pipeline_receive(self(), ^message)
    end

    test "flunks when pipeline does not receive the message" do
      message = "I am important message"

      assert_raise ExUnit.AssertionError, fn ->
        assert_pipeline_receive(self(), ^message, 0)
      end
    end
  end

  describe "assert_sink_received_event" do
    test "does not flunk when event is handled", %{state: state} do
      event = %Membrane.Event.Discontinuity{}
      Pipeline.handle_notification({:event, event}, :sink, state)
      assert_sink_received_event(self(), :sink, ^event)
    end

    test "flunks when event is not handled" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_sink_received_event(self(), :sink, _, 0)
      end
    end
  end

  describe "assert_sink_processed_buffer" do
    test "does not flunk when buffer is handled", %{state: state} do
      buffer = %Membrane.Buffer{payload: 255}
      Pipeline.handle_notification({:buffer, buffer}, :sink, state)
      assert_sink_processed_buffer(self(), :sink, ^buffer)
    end

    test "flunks when buffer is not handled" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_sink_processed_buffer(self(), :sink, _, 0)
      end
    end
  end

  describe "assert_start_of_stream" do
    test "does not flunk when :start_of_stream is handled by pipeline", %{state: state} do
      Pipeline.handle_notification({:start_of_stream, :input}, :sink, state)
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
      Pipeline.handle_notification({:end_of_stream, :input}, :sink, state)
      assert_end_of_stream(self(), :sink)
    end

    test "flunks when :end_of_stream is not handled by the pipeline" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_end_of_stream(self(), :sink, :input, 0)
      end
    end
  end
end
