defmodule Membrane.Testing.PipelineAssertionsTest do
  use ExUnit.Case
  alias Membrane.Testing.Pipeline
  import Membrane.Testing.Assertions

  # Note: Most of tests in this file are just to force compile valid macro invocations
  # Note: so compiler can find the errors.

  setup do
    [
      state: %{
        test_process: self()
      }
    ]
  end

  test "assert_pipeline_notified does not raise an error when notification is handled", %{
    state: state
  } do
    Pipeline.handle_notification(:notification, :element, state)
    assert_pipeline_notified(self(), :element, :notification)
  end

  test "assert_pipeline_playback_changed raises an error if invalid arguments are provided" do
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

  test "assert_pipeline_playback_changed does not raise an error when state change is handled", %{
    state: state
  } do
    Pipeline.handle_prepared_to_stopped(state)
    assert_pipeline_playback_changed(self(), :prepared, :stopped)
  end

  test "assert_pipeline_received", %{state: state} do
    message = "I am important message"
    Pipeline.handle_other(message, state)
    assert_pipeline_received(self(), ^message)
  end

  test "assert_sink_received_event", %{state: state} do
    event = %Membrane.Event.Discontinuity{}
    Pipeline.handle_notification({:event, event}, :sink, state)
    assert_sink_received_event(self(), :sink, ^event)
  end

  test "assert_sink_processed_buffer", %{state: state} do
    buffer = %Membrane.Buffer{payload: 255}
    Pipeline.handle_notification({:buffer, buffer}, :sink, state)
    assert_sink_processed_buffer(self(), :sink, ^buffer)
  end

  test "assert_start_of_stream", %{state: state} do
    Pipeline.handle_notification({:start_of_stream, :input}, :sink, state)
    assert_start_of_stream(self(), :sink)
  end

  test "assert_end_of_stream", %{state: state} do
    Pipeline.handle_notification({:end_of_stream, :input}, :sink, state)
    assert_end_of_stream(self(), :sink)
  end
end
