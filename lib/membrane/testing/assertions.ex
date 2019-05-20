defmodule Membrane.Testing.Assertions do
  @moduledoc """
  Assertions that can be used with `Membrane.Testing.Pipeline` in tests.

  All of assertions defined in this module work only in conjunction with
  `Membrane.Testing.Pipeline`.
  """
  require ExUnit.Assertions

  @default_timeout 2000

  # Note: pattern value_x = unquote(x) is used to workaround allowing both
  # Note: both function, value and variable to be passed as an argument.

  @doc false
  defmacro assert_message_receive(
             pid,
             pattern,
             failure_message \\ nil,
             timeout \\ @default_timeout
           ) do
    quote do
      import ExUnit.Assertions

      pid_value = unquote(pid)

      assert_receive(
        {Membrane.Testing.Pipeline, ^pid_value, unquote(pattern)},
        unquote(timeout),
        unquote(failure_message)
      )
    end
  end

  @doc """
  Asserts that pipeline got a notification from specific element.
  """
  defmacro assert_pipeline_notified(pipeline_pid, element_name, notification) do
    quote do
      element_name_value = unquote(element_name)

      assert_message_receive(
        unquote(pipeline_pid),
        {:handle_notification, {unquote(notification), ^element_name_value}}
      )
    end
  end

  @doc """
  Asserts that pipeline's playback state changed from one to another.

  Supplied change must be a valid one. Currently playback has 3
  `t:Membrane.Pipeline.playback_state_t/0`, namely:

   - `:stopped`
   - `:prepared`
   - `:playing`

   those states must change in a sequence so change from `:stopped` to
   `:prepared` is a valid one but from `:stopped` to `:
   prepared` is not.


       assert_pipeline_playback_changed(pipeline_pid, :prepared, :playing)
  """
  def assert_pipeline_playback_changed(
        pipeline_pid,
        previous_playback_state,
        current_playback_state
      ) do
    valid_changes = [
      {:stopped, :prepared},
      {:prepared, :playing},
      {:playing, :prepared},
      {:prepared, :stopped}
    ]

    if({previous_playback_state, current_playback_state} in valid_changes) do
      callback_name =
        Membrane.Core.PlaybackHandler.state_change_callback(
          previous_playback_state,
          current_playback_state
        )

      assert_message_receive(pipeline_pid, ^callback_name)
    else
      transitions =
        Enum.map(valid_changes, fn {from, to} ->
          "  " <> to_string(from) <> " -> " <> to_string(to)
        end)
        |> Enum.join("\n")

      raise """
      Transition from #{previous_playback_state} to #{current_playback_state} is not valid.
      Valid transitions are:
      #{transitions}
      """
    end
  end

  @doc """
  Asserts that pipeline received a message from another process.

  Such message would normally handled by `c:Membrane.Pipeline.handle_other/2`
  """
  defmacro assert_pipeline_received(pipeline_pid, message) do
    quote do
      assert_message_receive(unquote(pipeline_pid), {:handle_other, unquote(message)})
    end
  end

  @doc """
  Asserts that `Membrane.Testing.Sink` received an event.

  When a `Membrane.Testing.Sink` is part of `Membrane.Testing.Pipeline` you can
  assert wether it received an event matching a provided pattern.

      {:ok, pid} = Membrane.Testing.Pipeline.start_link(%Membrane.Testing.Pipeline.Options{
        elements: [
          ....,
          the_sink: %Membrane.Testing.Sink{}
        ]
      })

      assert_sink_received_event(pid, :the_sink, %Discontinuity{})
  """
  defmacro assert_sink_received_event(pipeline_pid, sink_name, event, timeout \\ @default_timeout) do
    quote do
      element_name_value = unquote(sink_name)

      assert_message_receive(
        unquote(pipeline_pid),
        {:handle_notification, {{:event, unquote(event)}, ^element_name_value}},
        unquote(timeout)
      )
    end
  end

  @doc """
  Asserts that `Membrane.Testing.Sink` received a buffer.

  When a `Membrane.Testing.Sink` is part of `Membrane.Testing.Pipeline` you can
  assert wether it received a buffer matching a provided pattern.

      {:ok, pid} = Membrane.Testing.Pipeline.start_link(%Membrane.Testing.Pipeline.Options{
        elements: [
          ....,
          the_sink: %Membrane.Testing.Sink{}
        ]
      })

  You can match for exact value:

      assert_sink_processed_buffer(pid, :the_sink ,%Membrane.Buffer{payload: ^specific_payload})

  You can also use pattern to extract data from the buffer:

      assert_sink_processed_buffer(pid, :sink, %Buffer{payload: <<data::16>> <> <<255>>})
      do_something(data)
  """
  defmacro assert_sink_processed_buffer(
             pipeline_pid,
             sink_name,
             pattern,
             timeout \\ @default_timeout
           ) do
    quote do
      element_name_value = unquote(sink_name)

      assert_message_receive(
        unquote(pipeline_pid),
        {:handle_notification, {{:buffer, unquote(pattern)}, ^element_name_value}},
        unquote(timeout)
      )
    end
  end

  @doc """
  Asserts that `Membrane.Testing.Pipeline` received or is going to receive
  `:start_of_stream` from specific element within the `timeout` period specified
  in milliseconds.

      assert_start_of_stream(pipeline_pid, :an_element)
  """
  def assert_start_of_stream(
        pipeline_pid,
        element_name,
        pad \\ :input,
        timeout \\ @default_timeout
      ) do
    assert_message_receive(
      pipeline_pid,
      {:handle_notification, {{:start_of_stream, ^pad}, ^element_name}},
      nil,
      timeout
    )
  end

  @doc """
  Asserts that `Membrane.Testing.Pipeline` received or is going to receive
  `:end_of_stream` from specific element within the `timeout` period specified
  in milliseconds.

      assert_end_of_stream(pipeline_pid, :an_element)
  """
  def assert_end_of_stream(pipeline_pid, element_name, pad \\ :input, timeout \\ @default_timeout) do
    assert_message_receive(
      pipeline_pid,
      {:handle_notification, {{:end_of_stream, ^pad}, ^element_name}},
      nil,
      timeout
    )
  end
end
