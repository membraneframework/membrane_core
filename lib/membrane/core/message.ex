defmodule Membrane.Core.Message do
  @moduledoc false
  # Record representing membrane internal message

  require Record

  Record.defrecord(:message, __MODULE__, type: nil, args: [])

  @type t :: {__MODULE__, type_t, args_t}
  @type type_t :: atom
  @type args_t :: list | any

  defmacro new(type, args \\ []) do
    quote do
      unquote(__MODULE__).message(type: unquote(type), args: unquote(args))
    end
  end

  @spec send(pid, type_t, args_t) :: t
  def send(pid, type, args \\ []) do
    Kernel.send(pid, message(type: type, args: args))
  end

  @spec self(type_t, args_t) :: t
  def self(type, args \\ []) do
    __MODULE__.send(self(), type, args)
  end

  @spec call(GenServer.server(), type_t, args_t, timeout()) :: term()
  def call(pid, type, args \\ [], timeout \\ 5000) do
    GenServer.call(pid, message(type: type, args: args), timeout)
  end
end
