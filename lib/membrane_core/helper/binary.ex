defmodule Membrane.Helper.Binary do
  use Membrane.Helper

  def int_rem(b, d) when is_binary(b) and is_integer(d) do
    len = b |> byte_size |> int_part(d)
    <<b::binary-size(len), r::binary>> = b
    {b, r}
  end

end
