defmodule Membrane.Helper do

  defmacro __using__(_args) do
    quote do
      import Membrane.Helper, only: [~>: 2]
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

  def stacktrace, do:
    Process.info(self(), :current_stacktrace)
      ~> ({:current_stacktrace, trace} -> trace)
      |> Exception.format_stacktrace
end
