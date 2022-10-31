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

  test "assert_pipeline_setup works", %{state: state} do
    Pipeline.handle_setup(context(), state)
    assert_pipeline_setup(self())

    assert_raise ExUnit.AssertionError, fn ->
      assert_pipeline_setup(self(), 0)
    end
  end

  test "assert_pipeline_play works", %{state: state} do
    Pipeline.handle_playing(context(), state)
    assert_pipeline_play(self())

    assert_raise ExUnit.AssertionError, fn ->
      assert_pipeline_play(self(), 0)
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

  describe "assert_sink_stream_format" do
    test "does not flunk when stream format is handled", %{state: state} do
      stream_format = %{property: :value}

      Pipeline.handle_child_notification(
        {:stream_format, :input, stream_format},
        :sink,
        context(),
        state
      )

      assert_sink_stream_format(self(), :sink, ^stream_format)
    end

    test "flunks when stream_format are not handled" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_sink_stream_format(self(), :sink, _, 0)
      end
    end
  end

  describe "refute_sink_stream_format" do
    test "flunks when stream format is handled", %{state: state} do
      stream_format = %{property: :value}

      Pipeline.handle_child_notification(
        {:stream_format, :input, stream_format},
        :sink,
        context(),
        state
      )

      assert_raise ExUnit.AssertionError, fn ->
        refute_sink_stream_format(self(), :sink, ^stream_format)
      end
    end

    test "does not flunk when stream format is not handled" do
      refute_sink_stream_format(self(), :sink, _, 0)
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
