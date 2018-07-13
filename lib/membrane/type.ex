defmodule Membrane.Type do
  @type try_t :: :ok | {:error, reason :: any}
  @type try_t(value) :: {:ok, value} | {:error, reason :: any}

  @type stateful_t(value, state) :: {value, state}

  @type stateful_try_t(state) :: stateful_t(try_t, state)
  @type stateful_try_t(value, state) :: stateful_t(try_t(value), state)
end
