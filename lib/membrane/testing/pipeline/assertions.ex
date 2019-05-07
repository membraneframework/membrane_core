defmodule Membrane.Testing.Pipeline.Assertions do
  @moduledoc """
  Assertions that can be used with `Membrane.Testing.Pipeline` in tests
  """

  # Used by ExUnit.Assertions.assert_receive/3
  import ExUnit.Assertions, only: [flunk: 1]

  defmacro assert_received_message(
             pid,
             pattern,
             failure_message \\ nil
           ) do
    import ExUnit.Assertions

    quote do
      assert_receive {Membrane.Testing.Pipeline, ^unquote(pid), unquote(pattern)},
                     20000,
                     unquote(failure_message)
    end
  end

  def assert_pipeline_notified(pipeline_pid, element_name, message) do
    assert_received_message(pipeline_pid, {^element_name, ^message})
  end

  def assert_pipeline_playback_changed(
        pipeline_pid,
        previous_playback_state,
        current_playback_state
      ) do
    callback_name =
      Membrane.Core.PlaybackHandler.state_change_callback(
        previous_playback_state,
        current_playback_state
      )

    assert_received_message(pipeline_pid, ^callback_name)
  end

  def assert_pipeline_received(pipeline_pid, message) do
    assert_received_message(pipeline_pid, {:handle_other, ^message})
  end

  defmacro assert_sink_processed_buffer(pipeline_pid, sink_name, pattern) do
    quote do
      assert_received_message(
        unquote(pipeline_pid),
        {:buffer, unquote(sink_name), unquote(pattern)}
      )
    end
  end
end
