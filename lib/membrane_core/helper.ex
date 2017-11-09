defmodule Membrane.Helper do
  import Kernel

  defmacro __using__(_args) do
    quote do
      import Membrane.Helper, only: [
        ~>: 2, ~>>: 2, provided: 2, int_part: 2]
      alias Membrane.Helper
    end
  end

  @compile {:inline, listify: 1, wrap_nil: 2, int_part: 2}

  def listify(list) when is_list list do list end
  def listify(non_list) do [non_list] end

  def wrap_nil(nil, reason), do: {:error, reason}
  def wrap_nil(v, _), do: {:ok, v}

  def result_status({:ok, _state}), do: :ok
  def result_status({{:ok, _res}, _state}), do: :ok
  def result_status({{:error, reason}, _state}), do: {:error, reason}
  def result_status({:error, reason}), do: {:error, reason}

  def int_part(x, d) when is_integer(x) and is_integer(d) do
    r = x |> rem(d)
    x - r
  end

  defmacro x ~> f do
    quote do
      case unquote x do unquote f end
    end
  end

  defmacro x ~>> f do
    default = quote do _ -> unquote(x) end
    quote do
      case unquote(x) do
        unquote(f ++ default)
      end
    end
  end

  defmacro provided(value, that: condition, else: default) do
    quote do
      if unquote condition do unquote value else unquote default end
    end
  end
  defmacro provided(value, that: condition) do
    quote do
      if unquote condition do unquote value else [] end
    end
  end
  defmacro provided(value, do: condition, else: default) do
    quote do
      if unquote condition do unquote value else unquote default end
    end
  end
  defmacro provided(value, do: condition) do
    quote do
      if unquote condition do unquote value else [] end
    end
  end
  defmacro provided(value, not: condition, else: default) do
    quote do
      if !(unquote condition) do unquote value else unquote default end
    end
  end
  defmacro provided(value, not: condition) do
    quote do
      if !(unquote condition) do unquote value else [] end
    end
  end

  defmacro stacktrace do
    quote do
      Process.info(self(), :current_stacktrace)
        ~> ({:current_stacktrace, trace} -> trace)
        |> Enum.drop(1) #in order to exclude `Process.info/2` call
        |> Exception.format_stacktrace
    end
  end
end
