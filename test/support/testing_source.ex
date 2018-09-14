defmodule Membrane.Integration.TestingSource do
  use Membrane.Element.Base.Source
  alias Membrane.Buffer

  def_source_pads source: {:always, :pull, :any}

  def_options buffer_generator: [
                type: :function,
                spec: (non_neg_integer, non_neg_integer -> [Membrane.Action.t()]),
                default: &__MODULE__.default_buf_gen/2
              ]

  @impl true
  def handle_init(opts) do
    {:ok, opts |> Map.merge(%{cnt: 0})}
  end

  @impl true
  def handle_demand(
        :source,
        size,
        :buffers,
        _ctx,
        %{cnt: cnt} = state
      ) do
    actions = state.buffer_generator.(cnt, size)

    {{:ok, actions}, %{state | cnt: cnt + length(actions)}}
  end

  def default_buf_gen(cnt, size) do
    cnt..(size + cnt - 1)
    |> Enum.map(fn cnt ->
      buf = %Buffer{payload: <<cnt>>}

      {:buffer, {:source, buf}}
    end)
  end
end
