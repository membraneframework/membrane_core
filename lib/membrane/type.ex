defmodule Membrane.Type do
  @type ok_t :: :ok
  @type ok_t(value) :: {:ok, value}
  @type error_t :: {:error, reason :: any}
  @type try_t :: ok_t | error_t
  @type try_t(value) :: ok_t(value) | error_t

  @type stateful_t(value, state) :: {value, state}

  @type stateful_try_t(state) :: stateful_t(try_t, state)
  @type stateful_try_t(value, state) :: stateful_t(try_t(value), state)
end
