defmodule Membrane.Testing.Assertions do
  @moduledoc """
  This module contains a set of assertion functions and macros.

  These assertions will work ONLY in conjunction with
  `Membrane.Testing.Pipeline` and ONLY when pid of tested pipeline is provided
  as an argument to these assertions.
  """

  @default_timeout 2000

  defp assert_receive_from_entity(assertion, entity, pid, pattern, timeout, failure_message) do
    quote do
      import ExUnit.Assertions
      pid_value = unquote(pid)

      unquote(assertion)(
        {unquote(entity), ^pid_value, unquote(pattern)},
        unquote(timeout),
        unquote(failure_message)
      )
    end
  end

  defp assert_receive_from_pipeline(pid, pattern, timeout, failure_message \\ nil) do
    assert_receive_from_entity(
      :assert_receive,
      Membrane.Testing.Pipeline,
      pid,
      pattern,
      timeout,
      failure_message
    )
  end

  defp refute_receive_from_pipeline(pid, pattern, timeout, failure_message \\ nil) do
    assert_receive_from_entity(
      :refute_receive,
      Membrane.Testing.Pipeline,
      pid,
      pattern,
      timeout,
      failure_message
    )
  end

  defp assert_receive_from_resource_guard(pid, pattern, timeout, failure_message \\ nil) do
    assert_receive_from_entity(
      :assert_receive,
      Membrane.Testing.MockResourceGuard,
      pid,
      pattern,
      timeout,
      failure_message
    )
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
          {:handle_child_notification,
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
          {:handle_child_notification,
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

  defmacro assert_pipeline_setup(pipeline, timeout \\ @default_timeout) do
    assert_receive_from_pipeline(pipeline, :setup, timeout)
  end

  defmacro assert_pipeline_play(pipeline, timeout \\ @default_timeout) do
    assert_receive_from_pipeline(pipeline, :play, timeout)
  end

  @doc """
  Asserts that pipeline received or will receive a message matching
  `message_pattern` from another process within the `timeout` period specified
  in milliseconds.

  The `message_pattern` must be a match pattern.

      assert_pipeline_receive(pid, :tick)

  Such call would flunk if the message `:tick` has not been handled by
  `c:Membrane.Parent.handle_info/3` within the `timeout`.
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
  `c:Membrane.Parent.handle_info/3`.
  """
  defmacro refute_pipeline_receive(pipeline, message_pattern, timeout \\ @default_timeout) do
    do_pipeline_receive(&refute_receive_from_pipeline/3, pipeline, message_pattern, timeout)
  end

  defp do_pipeline_receive(assertion, pipeline, message_pattern, timeout) do
    assertion.(pipeline, {:handle_info, message_pattern}, timeout)
  end

  @doc """
  Asserts that `Membrane.Testing.Sink` with name `sink_name` received or will
  receive stream format matching `pattern` within the `timeout` period specified in
  milliseconds.

  When the `Membrane.Testing.Sink` is a part of `Membrane.Testing.Pipeline` you
  can assert whether it received stream format matching provided pattern.
      import Membrane.ChildrenSpec
      children = [
          ....,
          child(:the_sink, %Membrane.Testing.Sink{})
      ]
      {:ok, pid} = Membrane.Testing.Pipeline.start_link(
        structure: children,
      )

  You can match for exact value:

      assert_sink_stream_format(pid, :the_sink , %StreamFormat{prop: ^value})

  You can also use pattern to extract data from the stream_format:

      assert_sink_stream_format(pid, :the_sink , %StreamFormat{prop: value})
      do_something(value)
  """
  defmacro assert_sink_stream_format(
             pipeline,
             element_name,
             stream_format_pattern,
             timeout \\ @default_timeout
           ) do
    do_sink_stream_format(
      &assert_receive_from_pipeline/3,
      pipeline,
      element_name,
      stream_format_pattern,
      timeout
    )
  end

  @doc """
  Asserts that `Membrane.Testing.Sink` with name `sink_name` has not received
  and will not receive stream format matching `stream_format_pattern` within the `timeout`
  period specified in milliseconds.

  Similarly as in the `assert_sink_stream_format/4` `the_sink` needs to be part of a
  `Membrane.Testing.Pipeline`.

      refute_sink_stream_format(pipeline, :the_sink, %StreamFormat{prop: ^val})

  Such expression will flunk if `the_sink` received or will receive stream_format with
  property equal to value of `val` variable.
  """
  defmacro refute_sink_stream_format(
             pipeline,
             element_name,
             stream_format_pattern,
             timeout \\ @default_timeout
           ) do
    do_sink_stream_format(
      &refute_receive_from_pipeline/3,
      pipeline,
      element_name,
      stream_format_pattern,
      timeout
    )
  end

  defp do_sink_stream_format(assertion, pipeline, sink_name, stream_format, timeout) do
    quote do
      element_name_value = unquote(sink_name)

      unquote(
        assertion.(
          pipeline,
          {:handle_child_notification,
           {quote do
              {:stream_format, :input, unquote(stream_format)}
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
      import Membrane.ChildrenSpec
      children = [
          ....,
          child(:the_sink, %Membrane.Testing.Sink{})
      ]
      {:ok, pid} = Membrane.Testing.Pipeline.start_link(
        structure: children,
        links: Membrane.ChildrenSpec.link_linear(children)
      )

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
          {:handle_child_notification,
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
          {:handle_child_notification,
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

  @doc """
  Asserts that a cleanup function was registered in `Membrane.Testing.MockResourceGuard`.
  """
  defmacro assert_resource_guard_register(
             mock_guard,
             function,
             tag,
             timeout \\ @default_timeout
           ) do
    assert_receive_from_resource_guard(
      mock_guard,
      {:register, {function, tag}},
      timeout
    )
  end

  @doc """
  Asserts that a tag was unregistered in `Membrane.Testing.MockResourceGuard`.
  """
  defmacro assert_resource_guard_unregister(
             mock_guard,
             tag,
             timeout \\ @default_timeout
           ) do
    assert_receive_from_resource_guard(
      mock_guard,
      {:unregister, tag},
      timeout
    )
  end

  @doc """
  Asserts that `Membrane.Testing.MockResourceGuard` was requested to cleanup a given tag.
  """
  defmacro assert_resource_guard_cleanup(
             mock_guard,
             tag,
             timeout \\ @default_timeout
           ) do
    assert_receive_from_resource_guard(
      mock_guard,
      {:cleanup, tag},
      timeout
    )
  end
end
