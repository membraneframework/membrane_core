defmodule Membrane.Element.Pad do
  @type name_t :: atom | {:dynamic, atom, non_neg_integer}

  defmacro is_pad_name(term) do
    quote do
      unquote(term) |> is_atom or
        (unquote(term) |> is_tuple and unquote(term) |> tuple_size == 3 and
           unquote(term) |> elem(0) == :dynamic and unquote(term) |> elem(1) |> is_atom and
           unquote(term) |> elem(2) |> is_integer)
    end
  end
end
