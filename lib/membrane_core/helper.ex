defmodule Membrane.Helper do

  def listify(list) when is_list list do list end
  def listify(non_list) do [non_list] end

  def x ~> f do
    f.(x)
  end

end
