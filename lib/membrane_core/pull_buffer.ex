defmodule Membrane.PullBuffer do
  alias Membrane.PullBuffer

  defstruct \
    sink: nil,
    q: nil,
    init_size: 0,
    preferred_size: 100,
    current_size: 0

  @qe Qex

  def new(sink, preferred_size, init_size \\ nil) do
    %PullBuffer{q: @qe.new, sink: sink, preferred_size: preferred_size, init_size: init_size || preferred_size}
  end

  def store(%PullBuffer{q: q, current_size: size} = pb, v) do
    %PullBuffer{pb | q: q |> @qe.push(v), current_size: size + 1}
  end

  def take(%PullBuffer{q: q, preferred_size: pref_size, init_size: init_size, current_size: size, sink: sink} = pb)
  when size > init_size do
    case q |> @qe.pop do
      {o, q} ->
        if size < pref_size do send sink, :membrane_demand end
        {o, %PullBuffer{pb | q: q, current_size: max(0, size - 1)}}
    end
  end
  def take(%PullBuffer{current_size: size, init_size: init_size} = pb)
  when size < init_size do
    {:empty, pb}
  end
  def take(%PullBuffer{} = pb) do
    take %PullBuffer{pb | init_size: -1}
  end

end
