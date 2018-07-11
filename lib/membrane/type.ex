defmodule Membrane.Type do
  @type ok_t :: :ok
  @type ok_t(value) :: {:ok, value}
  @type error_t :: {:error, reason :: any}
  @type maybe_t :: ok_t | error_t
  @type maybe_t(value) :: ok_t(value) | error_t

  @type stateful_t(value, state) :: {value, state}

  @type stateful_maybe_t(state) :: stateful_t(maybe_t, state)
  @type stateful_maybe_t(value, state) :: stateful_t(maybe_t(value), state)
end
