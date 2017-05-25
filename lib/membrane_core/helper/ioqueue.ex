defmodule Membrane.Helper.IOQueue do
  alias Membrane.Helper.IOQueue

  @qe Qex

  defstruct \
    q: nil

  def new, do: %IOQueue{q: @qe.new}
  def new init do
    new() |> push(init)
  end

  def push(q, binary) when is_binary binary do
    push q, [binary]
  end
  def push(%IOQueue{q: q}, iolist) when is_list iolist do
    %IOQueue{q: q |> @qe.push(iolist)}
  end

  def push_front(q, binary) when is_binary binary do
    push_front q, [binary]
  end
  def push_front(%IOQueue{q: q}, iolist) when is_list iolist do
    %IOQueue{q: q |> @qe.push_front(iolist)}
  end

  def pop %IOQueue{q: q} do
    {r, new_q} = @qe.pop q
    {r, %IOQueue{q: new_q}}
  end
  def pop q, :binary do
    case pop q do
      {{:value, []}, new_q} -> pop new_q, :binary
      {{:value, [h]}, new_q} -> {{:value, h}, new_q}
      {{:value, [h|t]}, new_q} -> {{:value, h}, new_q |> push_front(t)}
      empty -> empty
    end
  end
  def pop q, bytes do
    {{t, r}, q} = pop_bytes_r q, bytes
    {{t, r |> Enum.reverse}, q}
  end
  defp pop_bytes_r q, bytes, acc \\ [] do
    case pop q, :binary do
      {{:value, b}, new_q} ->
        case b do
          <<_::binary-size(bytes)>> ->
            {{:value, [b | acc]}, new_q}
          <<b_cut::binary-size(bytes)>> <> rem ->
            {{:value, [b_cut | acc]}, new_q |> push_front(rem)}
          _ -> pop_bytes_r new_q, bytes - byte_size(b), [b | acc]
        end
      {:empty, new_q} -> {{:empty, acc}, new_q}
    end
  end

  def empty q do
    case q |> pop(:binary) do
      {:empty, _} -> true
      _ -> false
    end
  end

  def byte_length %IOQueue{q: q} do
    q |> Enum.reduce(0, fn l, acc -> acc + IO.iodata_length l end)
  end

  def to_iolist %IOQueue{q: q} do
    q |> Enum.to_list |> List.flatten
  end

  def to_binary %IOQueue{q: q} do
    q |> to_iolist |> IO.iodata_to_binary
  end

end
