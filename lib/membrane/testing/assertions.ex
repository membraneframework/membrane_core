defmodule Membrane.Testing.Assertions do
  @moduledoc """
  This module contains a set of assertion functions and macros.

  These assertions will work ONLY in conjunction with
  `Membrane.Testing.Pipeline` and ONLY when pid of tested pipeline is provided
  as an argument to these assertions.
  """

  @default_timeout 2000

  defp do_assert_receive_from_pipeline(assertion, pid, pattern, timeout, failure_message) do
    quote do
      import ExUnit.Assertions
      pid_value = unquote(pid)

      unquote(assertion)(
        {Membrane.Testing.Pipeline, ^pid_value, unquote(pattern)},
        unquote(timeout),
        unquote(failure_message)
      )
    end
  end

  defp assert_receive_from_pipeline(pid, pattern, timeout, failure_message \\ nil) do
    do_assert_receive_from_pipeline(:assert_receive, pid, pattern, timeout, failure_message)
  end

  defp refute_receive_from_pipeline(pid, pattern, timeout, failure_message \\ nil) do
    do_assert_receive_from_pipeline(:refute_receive, pid, pattern, timeout, failure_message)
  end

  @doc """
  Asserts that pipeline received or will receive a notification from the element
  with name `element_name` within the `timeout` period specified in milliseconds.

  The `notification_pattern` must be a match pattern.

      assert_pipeline_notified(pipeline, :element_name, :hi)
  """
  defmacro assert_pipeline_notified(
             pipeline,
             element_name,
             notification_pattern,
             timeout \\ @default_timeout
           ) do
    quote do
      element_name_value = unquote(element_name)

      unquote(
        assert_receive_from_pipeline(
          pipeline,
          {:handle_notification,
           {notification_pattern,
            quote do
              ^element_name_value
            end}},
          timeout
        )
      )
    end
  end

  @doc """
  Refutes that pipeline received or will receive a notification from the element
  with name `element_name` within the `timeout` period specified in milliseconds.

  The `notification_pattern` must be a match pattern.

      refute_pipeline_notified(pipeline, :element_name, :hi)
  """
  defmacro refute_pipeline_notified(
             pipeline,
             element_name,
             notification_pattern,
             timeout \\ @default_timeout
           ) do
    quote do
      element_name_value = unquote(element_name)

      unquote(
        refute_receive_from_pipeline(
          pipeline,
          {:handle_notification,
           {notification_pattern,
            quote do
              ^element_name_value
            end}},
          timeout
        )
      )
    end
  end

  @doc """
  Asserts that a crash group within pipeline will be down within the `timeout` period specified in
  milliseconds.

  Usage example:

      assert_pipeline_crash_group_down(pipeline, :group_1)
  """
  defmacro assert_pipeline_crash_group_down(pipeline, group_name, timeout \\ @default_timeout) do
    quote do
      group_name_value = unquote(group_name)

      unquote(
        assert_receive_from_pipeline(
          pipeline,
          {:handle_crash_group_down,
           quote do
             ^group_name_value
           end},
          timeout
        )
      )
    end
  end

  @doc """
  Refutes that a crash group within pipeline won't be down within the `timeout` period specified in
  milliseconds.

  Usage example:

      refute_pipeline_crash_group_down(pipeline, :group_1)
  """
  defmacro refute_pipeline_crash_group_down(pipeline, group_name, timeout \\ @default_timeout) do
    quote do
      group_name_value = unquote(group_name)

      unquote(
        refute_receive_from_pipeline(
          pipeline,
          {:handle_crash_group_down,
           quote do
             ^group_name_value
           end},
          timeout
        )
      )
    end
  end

  @doc """
  Asserts that pipeline's playback state (see `Membrane.PlaybackState`)
  changed or will change from `previous_state` to `current_state` within
  the `timeout` period specified in milliseconds.

  The `prev_state` and `current_state` must be match patterns.

  Assertion can be either made by providing state before and after the change as
  atoms:

         assert_pipeline_playback_changed(pipeline, :prepared, :playing)

  Or by using an `_` to assert on change from any state to other:

        assert_pipeline_playback_changed(pipeline, _, :playing)
  """
  defmacro assert_pipeline_playback_changed(
             pipeline,
             previous_state,
             current_state,
             timeout \\ @default_timeout
           ) do
    with :ok <- validate_playback_change(previous_state, current_state) do
      pattern =
        quote do: {:playback_state_changed, unquote(previous_state), unquote(current_state)}

      assert_receive_from_pipeline(pipeline, pattern, timeout, nil)
    else
      {:error, flunk} -> flunk
    end
  end

  defp validate_playback_change(previous_state, current_state) do
    valid_changes = [
      {:stopped, :prepared},
      {:prepared, :playing},
      {:playing, :prepared},
      {:prepared, :stopped}
    ]

    are_arguments_values = is_atom(previous_state) and is_atom(current_state)

    if are_arguments_values and {previous_state, current_state} not in valid_changes do
      transitions =
        Enum.map_join(valid_changes, "\n", fn {from, to} ->
          "  " <> to_string(from) <> " -> " <> to_string(to)
        end)

      message = """
      Transition from #{previous_state} to #{current_state} is not valid.
      Valid transitions are:
      #{transitions}
      """

      flunk = quote do: flunk(unquote(message))
      {:error, flunk}
    else
      :ok
    end
  end

  @doc """
  Asserts that pipeline received or will receive a message matching
  `message_pattern` from another process within the `timeout` period specified
  in milliseconds.

  The `message_pattern` must be a match pattern.

      assert_pipeline_receive(pid, :tick)

  Such call would flunk if the message `:tick` has not been handled by
  `c:Membrane.Parent.handle_other/3` within the `timeout`.
  """
  defmacro assert_pipeline_receive(pipeline, message_pattern, timeout \\ @default_timeout) do
    do_pipeline_receive(&assert_receive_from_pipeline/3, pipeline, message_pattern, timeout)
  end

  @doc """
  Asserts that pipeline has not received and will not receive a message from
  another process matching `message_pattern` within the `timeout` period
  specified in milliseconds.

  The `message_pattern` must be a match pattern.


      refute_pipeline_receive(pid, :tick)


  Such call would flunk if the message `:tick` has been handled by
  `c:Membrane.Parent.handle_other/3`.
  """
  defmacro refute_pipeline_receive(pipeline, message_pattern, timeout \\ @default_timeout) do
    do_pipeline_receive(&refute_receive_from_pipeline/3, pipeline, message_pattern, timeout)
  end

  defp do_pipeline_receive(assertion, pipeline, message_pattern, timeout) do
    assertion.(pipeline, {:handle_other, message_pattern}, timeout)
  end

  @doc """
  Asserts that `Membrane.Testing.Sink` with name `sink_name` received or will
  receive caps matching `pattern` within the `timeout` period specified in
  milliseconds.

  When the `Membrane.Testing.Sink` is a part of `Membrane.Testing.Pipeline` you
  can assert whether it received caps matching provided pattern.

      {:ok, pid} = Membrane.Testing.Pipeline.start_link(%Membrane.Testing.Pipeline.Options{
        children: [
          ....,
          the_sink: %Membrane.Testing.Sink{}
        ]
      })

  You can match for exact value:

      assert_sink_caps(pid, :the_sink , %Caps{prop: ^value})

  You can also use pattern to extract data from the caps:

      assert_sink_caps(pid, :the_sink , %Caps{prop: value})
      do_something(value)
  """
  defmacro assert_sink_caps(pipeline, element_name, caps_pattern, timeout \\ @default_timeout) do
    do_sink_caps(&assert_receive_from_pipeline/3, pipeline, element_name, caps_pattern, timeout)
  end

  @doc """
  Asserts that `Membrane.Testing.Sink` with name `sink_name` has not received
  and will not receive caps matching `caps_pattern` within the `timeout`
  period specified in milliseconds.

  Similarly as in the `assert_sink_caps/4` `the_sink` needs to be part of a
  `Membrane.Testing.Pipeline`.

      refute_sink_caps(pipeline, :the_sink, %Caps{prop: ^val})

  Such expression will flunk if `the_sink` received or will receive caps with
  property equal to value of `val` variable.
  """
  defmacro refute_sink_caps(pipeline, element_name, caps_pattern, timeout \\ @default_timeout) do
    do_sink_caps(&refute_receive_from_pipeline/3, pipeline, element_name, caps_pattern, timeout)
  end

  defp do_sink_caps(assertion, pipeline, sink_name, caps, timeout) do
    quote do
      element_name_value = unquote(sink_name)

      unquote(
        assertion.(
          pipeline,
          {:handle_notification,
           {quote do
              {:caps, :input, unquote(caps)}
            end,
            quote do
              ^element_name_value
            end}},
          timeout
        )
      )
    end
  end

  @doc """
  Asserts that `Membrane.Testing.Sink` with name `sink_name` received or will
  receive a buffer matching `pattern` within the `timeout` period specified in
  milliseconds.

  When the `Membrane.Testing.Sink` is a part of `Membrane.Testing.Pipeline` you
  can assert whether it received a buffer matching provided pattern.

      {:ok, pid} = Membrane.Testing.Pipeline.start_link(%Membrane.Testing.Pipeline.Options{
        children: [
          ....,
          the_sink: %Membrane.Testing.Sink{}
        ]
      })

  You can match for exact value:

      assert_sink_buffer(pid, :the_sink ,%Membrane.Buffer{payload: ^specific_payload})

  You can also use pattern to extract data from the buffer:

      assert_sink_buffer(pid, :sink, %Buffer{payload: <<data::16>> <> <<255>>})
      do_something(data)
  """
  defmacro assert_sink_buffer(pipeline, sink_name, pattern, timeout \\ @default_timeout) do
    do_sink_buffer(&assert_receive_from_pipeline/3, pipeline, sink_name, pattern, timeout)
  end

  @doc """
  Asserts that `Membrane.Testing.Sink` with name `sink_name` has not received
  and will not receive a buffer matching `buffer_pattern` within the `timeout`
  period specified in milliseconds.

  Similarly as in the `assert_sink_buffer/4` `the_sink` needs to be part of a
  `Membrane.Testing.Pipeline`.

      refute_sink_buffer(pipeline, :the_sink, %Buffer{payload: <<0xA1, 0xB2>>})

  Such expression will flunk if `the_sink` received or will receive a buffer
  with payload `<<0xA1, 0xB2>>`.
  """
  defmacro refute_sink_buffer(pipeline, sink_name, pattern, timeout \\ @default_timeout) do
    do_sink_buffer(&refute_receive_from_pipeline/3, pipeline, sink_name, pattern, timeout)
  end

  defp do_sink_buffer(assertion, pipeline, sink_name, pattern, timeout) do
    quote do
      element_name_value = unquote(sink_name)

      unquote(
        assertion.(
          pipeline,
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
  Asserts that `Membrane.Testing.Sink` with name `sink_name` received or will
  receive an event within the `timeout` period specified in milliseconds.

  When a `Membrane.Testing.Sink` is part of `Membrane.Testing.Pipeline` you can
  assert whether it received an event matching a provided pattern.

      assert_sink_event(pid, :the_sink, %Discontinuity{})
  """
  defmacro assert_sink_event(pipeline, sink_name, event, timeout \\ @default_timeout) do
    do_sink_event(&assert_receive_from_pipeline/3, pipeline, sink_name, event, timeout)
  end

  @doc """
  Asserts that `Membrane.Testing.Sink` has not received and will not receive
  event matching provided pattern within the `timeout` period specified in
  milliseconds.

      refute_sink_event(pid, :the_sink, %Discontinuity{})
  """

  defmacro refute_sink_event(pipeline, sink_name, event, timeout \\ @default_timeout) do
    do_sink_event(&refute_receive_from_pipeline/3, pipeline, sink_name, event, timeout)
  end

  defp do_sink_event(assertion, pipeline, sink_name, event, timeout) do
    quote do
      element_name_value = unquote(sink_name)

      unquote(
        assertion.(
          pipeline,
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
  Asserts that `Membrane.Testing.Pipeline` received or is going to receive start_of_stream
  notification from the element with a name `element_name` within the `timeout` period
  specified in milliseconds.

      assert_start_of_stream(pipeline, :an_element)
  """
  defmacro assert_start_of_stream(
             pipeline,
             element_name,
             pad \\ :input,
             timeout \\ @default_timeout
           ) do
    assert_receive_from_pipeline(
      pipeline,
      {:handle_element_start_of_stream, {element_name, pad}},
      timeout
    )
  end

  @doc """
  Asserts that `Membrane.Testing.Pipeline` received or is going to receive end_of_stream
  notification about from the element with a name `element_name` within the `timeout` period
  specified in milliseconds.

      assert_end_of_stream(pipeline, :an_element)
  """
  defmacro assert_end_of_stream(
             pipeline,
             element_name,
             pad \\ :input,
             timeout \\ @default_timeout
           ) do
    assert_receive_from_pipeline(
      pipeline,
      {:handle_element_end_of_stream, {element_name, pad}},
      timeout
    )
  end
end
