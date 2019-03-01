defmodule Membrane.Testing.Pipeline.Assertions do
  @moduledoc """
  Assertions that can be used with `Membrane.Testing.Pipeline` in tests
  """

  @doc """
  Asserts that a message sent from `Membrane.Testing.Pipeline` matching `pattern` was or is going to be received
  within the `timeout` period, specified in milliseconds.

  The `pattern` argument must be a match pattern. Flunks with `failure_message`
  if a message matching `pattern` is not received.

  For example to wait for message indicating `handle_prepared_to_playing` callback
  was called:

      assert_receive_message :handle_prepared_to_playing
  """
  defmacro assert_receive_message(
             pattern,
             timeout \\ Application.fetch_env!(:ex_unit, :assert_receive_timeout),
             failure_message \\ nil
           ) do
    import ExUnit.Assertions, only: [assert_receive: 3]

    quote do
      assert_receive {Membrane.Testing.Pipeline, unquote(pattern)},
                     unquote(timeout),
                     unquote(failure_message)
    end
  end
end
