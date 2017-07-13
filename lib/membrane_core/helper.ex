defmodule Membrane.Helper do
  import Kernel, except: [send: 2]

  defmacro __using__(_args) do
    quote do
      import Membrane.Helper, only: [~>: 2, ~>>: 2]
      alias Membrane.Helper
    end
  end

  def listify(list) when is_list list do list end
  def listify(non_list) do [non_list] end

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

  def stacktrace, do:
    Process.info(self(), :current_stacktrace)
      ~> ({:current_stacktrace, trace} -> trace)
      |> Exception.format_stacktrace

  def send(pid, msg, from \\ self()) do
    Kernel.send pid, {msg, from}
    :ok
  end
end
