defmodule Membrane.Testing.Assertions do
  @moduledoc """
  This module contains a set of assertion functions and macros.

  These assertions will work ONLY in conjunction with
  `Membrane.Testing.Pipeline` and ONLY when pid of the process executing
  those functions and macros is an argument of said pipeline.
  """
  require ExUnit.Assertions

  @default_timeout 2000

  defp assert_message_receive(
         pid,
         pattern,
         timeout \\ @default_timeout,
         failure_message \\ nil
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
  Asserts that pipeline received or will receive a notification from specific
  element within the specified `timeout` period.
  """
  defmacro assert_pipeline_notified(
             pipeline_pid,
             element_name,
             notification,
             timeout \\ @default_timeout
           ) do
    quote do
      element_name_value = unquote(element_name)

      unquote(
        assert_message_receive(
          pipeline_pid,
          {:handle_notification,
           {notification,
            quote do
              ^element_name_value
            end}},
          timeout
        )
      )
    end
  end

  @doc """
  Asserts that pipeline's playback state changed or will change from one to
  another within the specified `timeout` period.

  Supplied change must be a valid one. Currently playback has 3
  `t:Membrane.Pipeline.playback_state_t/0`, namely:

   - `:stopped`
   - `:prepared`
   - `:playing`

   those states must change in a sequence so change from `:stopped` to
   `:prepared` is a valid one but from `:stopped` to `:
   playing` is not.


       assert_pipeline_playback_changed(pipeline_pid, :prepared, :playing)
  """
  defmacro assert_pipeline_playback_changed(
             pipeline_pid,
             previous_playback_state,
             current_playback_state,
             timeout \\ @default_timeout
           ) do
    valid_changes = [
      {:stopped, :prepared},
      {:prepared, :playing},
      {:playing, :prepared},
      {:prepared, :stopped}
    ]

    if({previous_playback_state, current_playback_state} in valid_changes) do
      callback =
        Membrane.Core.PlaybackHandler.state_change_callback(
          previous_playback_state,
          current_playback_state
        )

      quote do
        unquote(
          assert_message_receive(
            pipeline_pid,
            callback,
            timeout,
            nil
          )
        )
      end
    else
      transitions =
        Enum.map(valid_changes, fn {from, to} ->
          "  " <> to_string(from) <> " -> " <> to_string(to)
        end)
        |> Enum.join("\n")

      message = """
      Transition from #{previous_playback_state} to #{current_playback_state} is not valid.
      Valid transitions are:
      #{transitions}
      """

      quote do
        flunk(unquote(message))
      end
    end
  end

  @doc """
  Asserts that pipeline received or will receive a message from another process
  within the specified `timeout` period.

  Such a message would normally handled by `c:Membrane.Pipeline.handle_other/2`
  """
  defmacro assert_pipeline_receive(pipeline_pid, message_pattern, timeout \\ @default_timeout) do
    quote do
      unquote(
        assert_message_receive(
          pipeline_pid,
          {:handle_other, message_pattern},
          timeout
        )
      )
    end
  end

  @doc """
  Asserts that `Membrane.Testing.Sink` received or will receive an event within
  the `timeout` period specified in milliseconds.

  When a `Membrane.Testing.Sink` is part of `Membrane.Testing.Pipeline` you can
  assert whether it received an event matching a provided pattern.

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

      unquote(
        assert_message_receive(
          pipeline_pid,
          {:handle_notification,
           {{:event, event},
            quote do
              ^element_name_value
            end}},
          timeout
        )
      )
    end
  end

  @doc """
  Asserts that `Membrane.Testing.Sink` received or will receive a buffer within
  the `timeout` period specified in milliseconds.

  When a `Membrane.Testing.Sink` is a part of `Membrane.Testing.Pipeline` you
  can assert whether it received a buffer matching provided pattern.

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

      unquote(
        assert_message_receive(
          pipeline_pid,
          {:handle_notification,
           {{:buffer, pattern},
            quote do
              ^element_name_value
            end}},
          timeout
        )
      )
    end
  end

  @doc """
  Asserts that `Membrane.Testing.Pipeline` received or is going to receive
  `:start_of_stream` from a specific element within the `timeout` period
  specified in milliseconds.

      assert_start_of_stream(pipeline_pid, :an_element)
  """
  def assert_start_of_stream(
        pipeline_pid,
        element_name,
        pad \\ :input,
        timeout \\ @default_timeout
      ) do
    assert_pipeline_notified(
      pipeline_pid,
      element_name,
      {:start_of_stream, ^pad},
      timeout
    )
  end

  @doc """
  Asserts that `Membrane.Testing.Pipeline` received or is going to receive
  `:end_of_stream` from a specific element within the `timeout` period specified
  in milliseconds.

      assert_end_of_stream(pipeline_pid, :an_element)
  """
  def assert_end_of_stream(
        pipeline_pid,
        element_name,
        pad \\ :input,
        timeout \\ @default_timeout
      ) do
    assert_pipeline_notified(
      pipeline_pid,
      element_name,
      {:end_of_stream, ^pad},
      timeout
    )
  end
end
