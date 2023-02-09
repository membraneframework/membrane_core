defmodule Membrane.Core.Message do
  @moduledoc false

  # Record representing membrane internal message

  alias Membrane.Pad

  require Record

  Record.defrecord(:message, __MODULE__, type: nil, args: [], opts: [])

  @type t :: {__MODULE__, type, args, opts}
  @type type :: atom
  @type args :: list | any
  @type opts :: Keyword.t()

  defmacro new(type, args \\ [], opts \\ []) do
    quote do
      unquote(__MODULE__).message(type: unquote(type), args: unquote(args), opts: unquote(opts))
    end
  end

  @spec send(pid, type, args, opts) :: t
  def send(pid, type, args \\ [], opts \\ []) do
    Kernel.send(pid, message(type: type, args: args, opts: opts))
  end

  @spec self(type, args, opts) :: t
  def self(type, args \\ [], opts \\ []) do
    __MODULE__.send(self(), type, args, opts)
  end

  @spec call(GenServer.server(), type, args, opts, timeout()) ::
          term() | {:error, {:call_failure, any}}
  def call(pid, type, args \\ [], opts \\ [], timeout \\ 5000) do
    try do
      GenServer.call(pid, message(type: type, args: args, opts: opts), timeout)
    catch
      :exit, reason ->
        {:error, {:call_failure, reason}}
    end
  end

  @spec call!(GenServer.server(), type, args, opts, timeout()) :: term()
  def call!(pid, type, args \\ [], opts \\ [], timeout \\ 5000) do
    GenServer.call(pid, message(type: type, args: args, opts: opts), timeout)
  end

  @spec for_pad(t()) :: Pad.ref()
  def for_pad(message(opts: opts)), do: Keyword.get(opts, :for_pad)

  @spec set_for_pad(t(), Pad.ref()) :: t()
  def set_for_pad(message(opts: opts) = msg, pad),
    do: message(msg, opts: Keyword.put(opts, :for_pad, pad))
end
