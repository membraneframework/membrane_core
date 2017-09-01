defmodule Membrane.Helper do
  import Kernel

  defmacro __using__(_args) do
    quote do
      import Membrane.Helper, only: [
        ~>: 2, ~>>: 2, provided: 2, int_part: 2]
      alias Membrane.Helper
    end
  end

  def listify(list) when is_list list do list end
  def listify(non_list) do [non_list] end

  def wrap_nil(nil, reason), do: {:error, reason}
  def wrap_nil(v, _), do: {:ok, v}

  def int_part(x, d) when is_integer(x) and is_integer(d) do
    r = x |> rem(d)
    x - r
  end

  defmacro x ~> f do
    quote do
      case unquote x do unquote f end
    end
  end

  defmacro x ~>> {m, r} do
    quote do
      case unquote(x) do (
        unquote(m) -> unquote(r)
        _ -> unquote(x)
      ) end
    end
  end

  defmacro provided(value, that: condition, else: default) do
    quote do
      if unquote condition do unquote value else unquote default end
    end
  end
  defmacro provided(value, do: condition, else: default) do
    quote do
      if unquote condition do unquote value else unquote default end
    end
  end
  defmacro provided(value, not: condition, else: default) do
    quote do
      if !(unquote condition) do unquote value else unquote default end
    end
  end

  def stacktrace, do:
    Process.info(self(), :current_stacktrace)
      ~> ({:current_stacktrace, trace} -> trace)
      |> Exception.format_stacktrace
end
