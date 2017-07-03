defmodule Membrane.Helper do

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
