defmodule Membrane.Helper do

  def listify(list) when is_list list do list end
  def listify(non_list) do [non_list] end

  def x ~> f do
    f.(x)
  end

  def stacktrace, do:
    Process.info(self(), :current_stacktrace)
      ~> fn {:current_stacktrace, trace} -> trace end
      |> Exception.format_stacktrace
end
