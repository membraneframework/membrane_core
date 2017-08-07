defmodule Membrane.Helper do
  import Kernel

  defmacro __using__(_args) do
    quote do
      import Membrane.Helper, only: [~>: 2, ~>>: 2, provided: 2]
      alias Membrane.Helper
    end
  end

  def listify(list) when is_list list do list end
  def listify(non_list) do [non_list] end

  def wrap_nil(nil, reason), do: {:error, reason}
  def wrap_nil(v, _), do: {:ok, v}

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

  def provided(value, that: condition, else: default) do
    if condition do value else default end
  end
  def provided(value, do: condition, else: default) do
    if condition do value else default end
  end

  def stacktrace, do:
    Process.info(self(), :current_stacktrace)
      ~> ({:current_stacktrace, trace} -> trace)
      |> Exception.format_stacktrace
end
